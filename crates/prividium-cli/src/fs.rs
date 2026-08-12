use std::{
    fs,
    io::Write,
    os::unix::fs::{MetadataExt, PermissionsExt},
    path::Path,
};

use tempfile::NamedTempFile;

use crate::error::{AppError, Result};

pub fn ensure_regular_file(path: &Path, required_mode: Option<u32>) -> Result<()> {
    let metadata = fs::symlink_metadata(path).map_err(|error| {
        AppError::failed("FILE_NOT_FOUND", format!("{}: {error}", path.display()))
    })?;
    if metadata.file_type().is_symlink() || !metadata.is_file() {
        return Err(AppError::failed(
            "UNSAFE_FILE",
            format!(
                "{} must be a regular file, not a symbolic link",
                path.display()
            ),
        ));
    }
    if let Some(required) = required_mode {
        let actual = metadata.mode() & 0o777;
        if actual != required {
            return Err(AppError::failed(
                "UNSAFE_FILE_MODE",
                format!(
                    "{} must have mode {required:04o}; found {actual:04o}",
                    path.display()
                ),
            ));
        }
    }
    Ok(())
}

pub fn ensure_private_directory(path: &Path) -> Result<()> {
    let metadata = fs::symlink_metadata(path).map_err(|_| {
        AppError::failed(
            "RUNTIME_DIRECTORY_REQUIRED",
            format!(
                "prepare the protected runtime directory at {} as documented in runbooks/SETUP.md",
                path.display()
            ),
        )
    })?;
    if metadata.file_type().is_symlink() || !metadata.is_dir() {
        return Err(AppError::failed(
            "UNSAFE_RUNTIME_DIRECTORY",
            format!("{} must be a real directory", path.display()),
        ));
    }
    if metadata.uid() != current_uid()? || metadata.mode() & 0o777 != 0o700 {
        return Err(AppError::failed(
            "RUNTIME_DIRECTORY_PERMISSIONS",
            format!(
                "{} must be owned by the current user with mode 0700; see runbooks/SETUP.md",
                path.display()
            ),
        ));
    }
    Ok(())
}

pub fn atomic_write(path: &Path, mode: u32, contents: &[u8], replace: bool) -> Result<()> {
    let parent = path.parent().ok_or_else(|| {
        AppError::failed(
            "INVALID_PATH",
            format!("{} has no parent directory", path.display()),
        )
    })?;
    fs::create_dir_all(parent).map_err(|error| {
        AppError::failed(
            "DIRECTORY_CREATE_FAILED",
            format!("{}: {error}", parent.display()),
        )
    })?;
    if path
        .symlink_metadata()
        .is_ok_and(|metadata| metadata.file_type().is_symlink())
    {
        return Err(AppError::failed(
            "UNSAFE_FILE",
            format!("refusing to replace symbolic link {}", path.display()),
        ));
    }
    if !replace && path.exists() {
        return Err(AppError::failed(
            "FILE_EXISTS",
            format!("{} already exists", path.display()),
        ));
    }
    let mut temporary = NamedTempFile::new_in(parent).map_err(|error| {
        AppError::failed(
            "TEMPORARY_FILE_FAILED",
            format!("{}: {error}", parent.display()),
        )
    })?;
    temporary
        .as_file_mut()
        .set_permissions(fs::Permissions::from_mode(mode))
        .map_err(|error| {
            AppError::failed(
                "FILE_PERMISSION_FAILED",
                format!("{}: {error}", path.display()),
            )
        })?;
    temporary
        .write_all(contents)
        .and_then(|_| temporary.as_file_mut().sync_all())
        .map_err(|error| {
            AppError::failed("FILE_WRITE_FAILED", format!("{}: {error}", path.display()))
        })?;
    if replace {
        temporary.persist(path)
    } else {
        temporary.persist_noclobber(path)
    }
    .map_err(|error| {
        AppError::failed(
            "FILE_PUBLISH_FAILED",
            format!("{}: {}", path.display(), error.error),
        )
    })?;
    Ok(())
}

pub fn current_uid() -> Result<u32> {
    let status = fs::read_to_string("/proc/self/status")
        .ok()
        .and_then(|document| {
            document.lines().find_map(|line| {
                line.strip_prefix("Uid:")?
                    .split_whitespace()
                    .next()?
                    .parse()
                    .ok()
            })
        });
    if let Some(uid) = status {
        return Ok(uid);
    }
    let output = std::process::Command::new("id")
        .arg("-u")
        .output()
        .map_err(|error| AppError::failed("UID_LOOKUP_FAILED", error.to_string()))?;
    String::from_utf8_lossy(&output.stdout)
        .trim()
        .parse()
        .map_err(|_| AppError::failed("UID_LOOKUP_FAILED", "id -u returned a nonnumeric value"))
}
