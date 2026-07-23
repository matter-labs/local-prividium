window['##runtimeConfig'] = {
    appEnvironment: 'prividium-sandbox',
    environmentConfig: {
        networks: [
            {
                apiUrl: 'https://explorer-api.__SANDBOX_DOMAIN__',
                hostnames: ['explorer.__SANDBOX_DOMAIN__'],
                icon: '/images/icons/zksync-arrows.svg',
                l2ChainId: __L2_CHAIN_ID__,
                l2NetworkName: '__CHAIN_NAME__',
                maintenance: false,
                name: '__CHAIN_NAME__',
                published: true,
                rpcUrl: 'https://api.__SANDBOX_DOMAIN__/rpc',
                baseTokenAddress: '0x000000000000000000000000000000000000800A',
                prividium: true,
                userPanelUrl: 'https://app.__SANDBOX_DOMAIN__'
            }
        ]
    }
};
