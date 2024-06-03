BEGIN;

DROP FUNCTION IF EXISTS starkflare_api.get_top_transactions_by_steps();

CREATE OR REPLACE FUNCTION starkflare_api.get_top_transactions_by_steps()
RETURNS TABLE (
    tx_hash VARCHAR(66),
    steps_number INTEGER,
    tx_timestamp INTEGER,
    block_number INTEGER
)
AS $$
DECLARE
    current_period_start TIMESTAMP := DATE_TRUNC('day', NOW() - INTERVAL '7 days');
    current_period_end TIMESTAMP := DATE_TRUNC('day', NOW());
BEGIN
    RETURN QUERY
    WITH ranked_transactions AS (
        SELECT 
            t.tx_hash,
            t.steps_number,
            t.timestamp AS tx_timestamp,
            t.block_number,
            ROW_NUMBER() OVER (PARTITION BY t.tx_hash ORDER BY t.steps_number DESC) AS rnk
        FROM starkflare_api.account_calls t
        WHERE t.timestamp >= EXTRACT(EPOCH FROM current_period_start)
          AND t.timestamp < EXTRACT(EPOCH FROM current_period_end)
    )
    SELECT 
        r.tx_hash,
        r.steps_number,
        r.tx_timestamp,
        r.block_number
    FROM ranked_transactions r
    WHERE rnk = 1
    ORDER BY steps_number DESC
    LIMIT 10;
END;
$$ LANGUAGE plpgsql;

DROP FUNCTION IF EXISTS starkflare_api.get_common_data();

CREATE OR REPLACE FUNCTION starkflare_api.get_common_data()
RETURNS json
AS $$
DECLARE
    user_stats json;
    top_transactions json;
    transaction_stats json;
    top_contracts_by_steps json;
BEGIN
    -- Fetch user stats
    SELECT json_build_object(
        'unique_users_last_7_days', user_stats.unique_users_last_7_days,
        'new_users_last_7_days', user_stats.new_users_last_7_days,
        'lost_users_last_7_days', user_stats.lost_users_last_7_days
    ) INTO user_stats
    FROM starkflare_api.get_user_stats() AS user_stats;

    -- Fetch transaction stats
    SELECT json_build_object(
        'transactions_count_last_7_days', transaction_stats.transactions_count_last_7_days,
        'steps_number_last_7_days', transaction_stats.steps_number_last_7_days
    ) INTO transaction_stats 
    FROM starkflare_api.get_transaction_stats() AS transaction_stats;

    -- Fetch top contracts by steps stats
    SELECT json_agg(
        json_build_object(
            'contract_address', contracts.contract_hash,
            'steps_number', contracts.contract_steps,
            'steps_percentage', contracts.contract_steps_percentage
        )
    ) INTO top_contracts_by_steps
    FROM starkflare_api.get_top_contracts_by_steps() AS contracts;

    -- Fetch top transactions by steps
    SELECT json_agg(json_build_object(
        'tx_hash', tx.tx_hash,
        'steps_consumed', tx.steps_number,
        'tx_timestamp', tx.tx_timestamp,
        'block_number', tx.block_number
    )) INTO top_transactions
    FROM starkflare_api.get_top_transactions_by_steps() AS tx;

    RETURN json_build_object(
        'user_stats', user_stats,
        'transaction_stats', transaction_stats,
        'top_contracts_by_steps', top_contracts_by_steps,
        'top_transactions_by_steps', top_transactions
    );
END;
$$ LANGUAGE plpgsql;

COMMIT;