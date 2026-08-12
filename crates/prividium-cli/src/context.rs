use std::{
    env,
    path::{Path, PathBuf},
};

use crate::error::{AppError, Result};

#[derive(Debug, Clone)]
pub struct Context {
    pub repo_root: PathBuf,
    pub runtime_dir: PathBuf,
}

impl Context {
    pub fn discover() -> Result<Self> {
        let repo_root = env::var_os("PRIVIDIUM_REPO_ROOT")
            .map(PathBuf::from)
            .filter(|path| Self::looks_like_repo(path))
            .or_else(|| env::current_dir().ok().and_then(Self::find_repo))
            .or_else(|| {
                env::current_exe()
                    .ok()
                    .and_then(|path| Self::find_repo(path.parent()?))
            })
            .ok_or_else(|| {
                AppError::failed(
                    "REPOSITORY_NOT_FOUND",
                    "run prividium from a local-prividium repository checkout",
                )
            })?;

        Ok(Self {
            repo_root,
            runtime_dir: PathBuf::from("/etc/prividium/runtime"),
        })
    }

    pub fn encrypted_environment(&self) -> PathBuf {
        self.repo_root.join("deployment/secrets/sandbox.enc.env")
    }

    pub fn age_key(&self) -> PathBuf {
        self.repo_root.join("deployment/secrets/age.key")
    }

    pub fn runtime_environment(&self) -> PathBuf {
        self.runtime_dir.join("sandbox.env")
    }

    pub fn public(&self, name: &str) -> PathBuf {
        self.repo_root.join("deployment/public").join(name)
    }

    fn find_repo(start: impl AsRef<Path>) -> Option<PathBuf> {
        start
            .as_ref()
            .ancestors()
            .find(|candidate| Self::looks_like_repo(candidate))
            .map(Path::to_path_buf)
    }

    fn looks_like_repo(path: &Path) -> bool {
        path.join("deployment/versions.lock.yaml").is_file()
            && path.join("compose/compose.yaml").is_file()
    }
}
