IMAGE = "bbusa/op:latest"

ENVRC_PATH = "/workspace/optimism/.envrc"

FACTORY_DEPLOYER_ADDRESS = "0x3fAB184622Dc19b6109349B94811493BF2a45362"
FACTORY_DEPLOYER_CODE = "0xf8a58085174876e800830186a08080b853604580600e600039806000f350fe7fffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffe03601600081602082378035828234f58015156039578182fd5b8082525050506014600cf31ba02222222222222222222222222222222222222222222222222222222222222222a02222222222222222222222222222222222222222222222222222222222222222"


def launch_contract_deployer(
    plan,
    el_rpc_http_url,
    cl_rpc_http_url,
    priv_key,
    l1_chain_id,
    l2_chain_id,
    l1_block_time,
    l2_block_time,
):
    op_genesis = plan.run_sh(
        description="Deploying L2 contracts (takes a few minutes (30 mins for mainnet preset - 4 mins for minimal preset) -- L1 has to be finalized first)",
        image=IMAGE,
        env_vars={
            "WEB3_RPC_URL": str(el_rpc_http_url),
            "WEB3_PRIVATE_KEY": str(priv_key),
            "CL_RPC_URL": str(cl_rpc_http_url),
            "FUND_VALUE": "10",
            "DEPLOYMENT_OUTFILE": "/workspace/optimism/packages/contracts-bedrock/deployments/"
            + str(l1_chain_id)
            + "/kurtosis.json",
            "DEPLOY_CONFIG_PATH": "/workspace/optimism/packages/contracts-bedrock/deploy-config/getting-started.json",
            "STATE_DUMP_PATH": "/workspace/optimism/packages/contracts-bedrock/deployments/"
            + str(l1_chain_id)
            + "/state-dump.json",
            "L1_RPC_KIND": "any",
            "L1_RPC_URL": str(el_rpc_http_url),
            "L1_CHAIN_ID": str(l1_chain_id),
            "L2_CHAIN_ID": str(l2_chain_id),
            "L1_BLOCK_TIME": str(l1_block_time),
            "L2_BLOCK_TIME": str(l2_block_time),
            "DEPLOYMENT_CONTEXT": "getting-started",
        },
        store=[
            StoreSpec(src="/network-configs", name="op-genesis-configs"),
        ],
        run=" && ".join(
            [
                "./packages/contracts-bedrock/scripts/getting-started/wallets.sh >> {0}".format(
                    ENVRC_PATH
                ),
                "sed -i '1d' {0}".format(
                    ENVRC_PATH
                ),  # Remove the first line (not commented out)
                "echo 'export IMPL_SALT=$(openssl rand -hex 32)' >> {0}".format(
                    ENVRC_PATH
                ),
                ". {0}".format(ENVRC_PATH),
                "mkdir -p /network-configs",
                "web3 transfer $FUND_VALUE to $GS_ADMIN_ADDRESS",  # Fund Admin
                "sleep 3",
                "web3 transfer $FUND_VALUE to $GS_BATCHER_ADDRESS",  # Fund Batcher
                "sleep 3",
                "web3 transfer $FUND_VALUE to $GS_PROPOSER_ADDRESS",  # Fund Proposer
                "sleep 3",
                "web3 transfer $FUND_VALUE to {0}".format(
                    FACTORY_DEPLOYER_ADDRESS
                ),  # Fund Factory deployer
                "sleep 3",
                # sleep till chain is finalized
                "while true; do sleep 3; echo 'Chain is not yet finalized...'; if [ \"$(curl -s $CL_RPC_URL/eth/v1/beacon/states/head/finality_checkpoints | jq -r '.data.finalized.epoch')\" != \"0\" ]; then echo 'Chain is finalized!'; break; fi; done",
                "cd /workspace/optimism/packages/contracts-bedrock",
                "./scripts/getting-started/config.sh",
                "cast publish --rpc-url $WEB3_RPC_URL {0}".format(
                    FACTORY_DEPLOYER_CODE
                ),
                "sleep 12",
                "forge script scripts/Deploy.s.sol:Deploy --private-key $GS_ADMIN_PRIVATE_KEY --broadcast --rpc-url $L1_RPC_URL",
                "sleep 3",
                "CONTRACT_ADDRESSES_PATH=$DEPLOYMENT_OUTFILE forge script scripts/L2Genesis.s.sol:L2Genesis --sig 'runWithStateDump()' --chain-id $L2_CHAIN_ID",
                "cd /workspace/optimism/op-node",
                "go run cmd/main.go genesis l2 \
                            --l1-rpc $L1_RPC_URL \
                            --deploy-config $DEPLOY_CONFIG_PATH \
                            --l2-allocs $STATE_DUMP_PATH \
                            --l1-deployments $DEPLOYMENT_OUTFILE \
                            --outfile.l2 /network-configs/genesis.json \
                            --outfile.rollup /network-configs/rollup.json",
                "mv $DEPLOY_CONFIG_PATH /network-configs/getting-started.json",
                "mv $DEPLOYMENT_OUTFILE /network-configs/kurtosis.json",
                "mv $STATE_DUMP_PATH /network-configs/state-dump.json",
            ]
        ),
        wait="2000s",
    )
    return op_genesis.files_artifacts[0]
