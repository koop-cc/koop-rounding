DROP FUNCTION IF EXISTS kp__rounding_orders(bigint);

CREATE OR REPLACE FUNCTION kp__rounding_orders(
    distr_off_id bigint
) RETURNS TABLE(
    id bigint,
    distributions_offer bigint,
    basket bigint,
    quantity numeric,
    quantity_adjusted numeric,
    quantity_adjusted_locked boolean,
    rounding_error kp_enum_rounding_error
) LANGUAGE plpgsql AS $$
DECLARE
    debugMsgs JSONB;
    debugOriginOffer JSONB;
    debugOriginOrders JSONB;
    debugFinalOrders JSONB;
    offerRecord RECORD;
    roundingStepSize NUMERIC := 0;
    unitTotalSize NUMERIC := 0;
    totalOrderedQuantity NUMERIC := 0;
    orderRecord RECORD;
    targetTotalQuantity NUMERIC;
    scaleFactor NUMERIC;
    adjustedQuantity NUMERIC;
    currentTotalAdjusted NUMERIC := 0;
    remainingDifference NUMERIC;
    nonLockedOrderCount INTEGER;
    remainingDiffStep NUMERIC;
    remainingDiffSteps INTEGER;
    remainingDiffPos INTEGER;
    finalOrder RECORD;
    adjustedOrder RECORD;
    startTime TIMESTAMP;
    finalTotalOrderedQuantity NUMERIC;
    finalTotalAdjustedQuantity NUMERIC;
BEGIN
    RAISE LOG 'kp__rounding_orders(%)', distr_off_id;

    -- Start time
    startTime := CLOCK_TIMESTAMP();

    -- Result of the adjusted orders
    CREATE TEMP TABLE adjusted_orders(
        id bigint,
        distributions_offer bigint,
        basket bigint,
        quantity numeric,
        quantity_adjusted numeric,
        quantity_adjusted_locked boolean,
        rounding_error kp_enum_rounding_error
    );

    -- Select all valid distributions orders without quantity 0 and create a temporary table
    CREATE TEMP TABLE valid_orders AS
    SELECT
        distributions_orders.id,
        distributions_orders.distributions_offer,
        distributions_orders.basket,
        distributions_orders.quantity,
        distributions_orders.quantity_adjusted,
        distributions_orders.quantity_adjusted_locked,
        distributions_orders.rounding_error
    FROM distributions_orders
    WHERE distributions_orders.distributions_offer = distr_off_id AND distributions_orders.quantity <> 0;

    IF NOT EXISTS (SELECT 1 FROM valid_orders) THEN
        debugMsgs := COALESCE(debugMsgs, '[]'::jsonb) || jsonb_build_array('Error: No distributions orders with quantity larger than 0 found for offer id ' || distr_off_id || '. Maybe you dont have access to this distribution, check your role and in which koops you have access.');
        INSERT INTO distributions_orders_rounding
            (
                distributions_offer,
                messages,
                origin_offer,
                origin_orders,
                remain_diff,
                target_total_quantity,
                scale_factor,
                adjusted_orders,
                total_ordered,
                total_adjusted,
                time_taken_ms
            )
            VALUES (
                NULL, -- distributions_offer,
                debugMsgs, -- messages,
                NULL, -- origin_offer,
                NULL, -- origin_orders,
                NULL, -- remain_diff,
                NULL, -- target_total_quantity,
                NULL, -- scale_factor,
                NULL, -- adjusted_orders,
                NULL, -- total_ordered,
                NULL, -- total_adjusted,
                EXTRACT(EPOCH FROM(CLOCK_TIMESTAMP() - startTime)) * 1000 -- time_taken_ms
            );

        RETURN QUERY SELECT * FROM adjusted_orders;
        DROP TABLE IF EXISTS valid_orders, adjusted_orders, final_orders, origin_orders;
        RETURN;
    END IF;

    -- Select the distribution offer details
    SELECT
        distributions_offers.id,
        (distributions_offers.cloned_offer->>'unit_count')::NUMERIC AS unit_count,
        (distributions_offers.cloned_offer->>'unit_size')::NUMERIC AS unit_size,
        (distributions_offers.cloned_offer->>'step_size')::NUMERIC AS step_size,
        (distributions_offers.cloned_offer->>'rounding_step_size')::NUMERIC AS rounding_step_size,
        distributions_offers.total_adjusted
    INTO offerRecord
    FROM distributions_offers
    WHERE distributions_offers.id = distr_off_id;

    debugOriginOffer := row_to_json(offerRecord);

    -- Check offer requirements setups
    IF offerRecord IS NULL THEN
        debugMsgs := COALESCE(debugMsgs, '[]'::jsonb) || jsonb_build_array('Error: No offer found with id ' || distr_off_id);
        INSERT INTO distributions_orders_rounding
            (
                distributions_offer,
                messages,
                origin_offer,
                origin_orders,
                remain_diff,
                target_total_quantity,
                scale_factor,
                adjusted_orders,
                total_ordered,
                total_adjusted,
                time_taken_ms
            )
            VALUES (
                distr_off_id, -- distributions_offer,
                debugMsgs, -- messages,
                NULL, -- origin_offer,
                NULL, -- origin_orders,
                NULL, -- remain_diff,
                NULL, -- target_total_quantity,
                NULL, -- scale_factor,
                NULL, -- adjusted_orders,
                NULL, -- total_ordered,
                NULL, -- total_adjusted,
                EXTRACT(EPOCH FROM(CLOCK_TIMESTAMP() - startTime)) * 1000 -- time_taken_ms
            );

        RETURN QUERY SELECT * FROM adjusted_orders;
        DROP TABLE IF EXISTS valid_orders, adjusted_orders, final_orders, origin_orders;
        RETURN;
    END IF;
    IF offerRecord.step_size IS NULL THEN
        debugMsgs := COALESCE(debugMsgs, '[]'::jsonb) || jsonb_build_array('Error: step_size of offer with id ' || distr_off_id || ' is invalid');
        INSERT INTO distributions_orders_rounding
            (
                distributions_offer,
                messages,
                origin_offer,
                origin_orders,
                remain_diff,
                target_total_quantity,
                scale_factor,
                adjusted_orders,
                total_ordered,
                total_adjusted,
                time_taken_ms
            )
            VALUES (
                distr_off_id, -- distributions_offer,
                debugMsgs, -- messages,
                debugOriginOffer, -- origin_offer,
                NULL, -- origin_orders,
                NULL, -- remain_diff,
                NULL, -- target_total_quantity,
                NULL, -- scale_factor,
                NULL, -- adjusted_orders,
                NULL, -- total_ordered,
                NULL, -- total_adjusted,
                EXTRACT(EPOCH FROM(CLOCK_TIMESTAMP() - startTime)) * 1000 -- time_taken_ms
            );

        RETURN QUERY SELECT * FROM adjusted_orders;
        DROP TABLE IF EXISTS valid_orders, adjusted_orders, final_orders, origin_orders;
        RETURN;
    END IF;
    IF offerRecord.rounding_step_size IS NULL THEN
        debugMsgs := COALESCE(debugMsgs, '[]'::jsonb) || jsonb_build_array('Error: rounding_step_size of offer with id ' || distr_off_id || ' is invalid');
        INSERT INTO distributions_orders_rounding
            (
                distributions_offer,
                messages,
                origin_offer,
                origin_orders,
                remain_diff,
                target_total_quantity,
                scale_factor,
                adjusted_orders,
                total_ordered,
                total_adjusted,
                time_taken_ms
            )
            VALUES (
                distr_off_id, -- distributions_offer,
                debugMsgs, -- messages,
                debugOriginOffer, -- origin_offer,
                NULL, -- origin_orders,
                NULL, -- remain_diff,
                NULL, -- target_total_quantity,
                NULL, -- scale_factor,
                NULL, -- adjusted_orders,
                NULL, -- total_ordered,
                NULL, -- total_adjusted,
                EXTRACT(EPOCH FROM(CLOCK_TIMESTAMP() - startTime)) * 1000 -- time_taken_ms
            );

        RETURN QUERY SELECT * FROM adjusted_orders;
        DROP TABLE IF EXISTS valid_orders, adjusted_orders, final_orders, origin_orders;
        RETURN;
    END IF;
    IF offerRecord.unit_size IS NULL THEN
        debugMsgs := COALESCE(debugMsgs, '[]'::jsonb) || jsonb_build_array('Error: unit_size of offer with id ' || distr_off_id || ' is invalid');
        INSERT INTO distributions_orders_rounding
            (
                distributions_offer,
                messages,
                origin_offer,
                origin_orders,
                remain_diff,
                target_total_quantity,
                scale_factor,
                adjusted_orders,
                total_ordered,
                total_adjusted,
                time_taken_ms
            )
            VALUES (
                distr_off_id, -- distributions_offer,
                debugMsgs, -- messages,
                debugOriginOffer, -- origin_offer,
                NULL, -- origin_orders,
                NULL, -- remain_diff,
                NULL, -- target_total_quantity,
                NULL, -- scale_factor,
                NULL, -- adjusted_orders,
                NULL, -- total_ordered,
                NULL, -- total_adjusted,
                EXTRACT(EPOCH FROM(CLOCK_TIMESTAMP() - startTime)) * 1000 -- time_taken_ms
            );

        RETURN QUERY SELECT * FROM adjusted_orders;
        DROP TABLE IF EXISTS valid_orders, adjusted_orders, final_orders, origin_orders;
        RETURN;
    END IF;
    -- unit_count is by default not null, but you never know if that changes in the future
    IF offerRecord.unit_count IS NULL THEN
        debugMsgs := COALESCE(debugMsgs, '[]'::jsonb) || jsonb_build_array('Error: unit_count of offer with id ' || distr_off_id || ' is invalid');
        INSERT INTO distributions_orders_rounding
            (
                distributions_offer,
                messages,
                origin_offer,
                origin_orders,
                remain_diff,
                target_total_quantity,
                scale_factor,
                adjusted_orders,
                total_ordered,
                total_adjusted,
                time_taken_ms
            )
            VALUES (
                distr_off_id, -- distributions_offer,
                debugMsgs, -- messages,
                debugOriginOffer, -- origin_offer,
                NULL, -- origin_orders,
                NULL, -- remain_diff,
                NULL, -- target_total_quantity,
                NULL, -- scale_factor,
                NULL, -- adjusted_orders,
                NULL, -- total_ordered,
                NULL, -- total_adjusted,
                EXTRACT(EPOCH FROM(CLOCK_TIMESTAMP() - startTime)) * 1000 -- time_taken_ms
            );

        RETURN QUERY SELECT * FROM adjusted_orders;
        DROP TABLE IF EXISTS valid_orders, adjusted_orders, final_orders, origin_orders;
        RETURN;
    END IF;

    -- Assign rounding step size
    roundingStepSize := offerRecord.rounding_step_size;

    -- Ensure step_size is not smaller than rounding_step_size
    IF offerRecord.step_size < offerRecord.rounding_step_size THEN
        debugMsgs := COALESCE(debugMsgs, '[]'::jsonb) || jsonb_build_array('Warning: Rounding step size is larger than step size, setting rounding step size to step size.');
        roundingStepSize := offerRecord.step_size;
    END IF;

    -- Total size and total ordered quantity
    unitTotalSize := offerRecord.unit_size * offerRecord.unit_count;

    -- Select all distributions orders before updating
    CREATE TEMP TABLE origin_orders AS
    SELECT
        distributions_orders.id,
        distributions_orders.distributions_offer,
        distributions_orders.basket,
        distributions_orders.quantity,
        distributions_orders.quantity_adjusted,
        distributions_orders.quantity_adjusted_locked,
        distributions_orders.rounding_error
    FROM distributions_orders
    WHERE distributions_orders.distributions_offer = distr_off_id;

    debugOriginOrders := (SELECT json_agg(row_to_json(origin_orders)) FROM origin_orders);

    -- Calculate total ordered quantity
    SELECT SUM(
        CASE
            WHEN valid_orders.quantity_adjusted_locked THEN valid_orders.quantity_adjusted
            ELSE valid_orders.quantity
        END
    ) INTO totalOrderedQuantity
    FROM valid_orders;

    IF totalOrderedQuantity <= 0 THEN
        debugMsgs := COALESCE(debugMsgs, '[]'::jsonb) || jsonb_build_array('Error: Total ordered quantity considering quantity_adjusted_locked and sum up quantity_adjusted or then quantity is 0 or less, exit function.');
        INSERT INTO distributions_orders_rounding
            (
                distributions_offer,
                messages,
                origin_offer,
                origin_orders,
                remain_diff,
                target_total_quantity,
                scale_factor,
                adjusted_orders,
                total_ordered,
                total_adjusted,
                time_taken_ms
            )
            VALUES (
                distr_off_id, -- distributions_offer,
                debugMsgs, -- messages,
                debugOriginOffer, -- origin_offer,
                debugOriginOrders, -- origin_orders,
                NULL, -- remain_diff,
                NULL, -- target_total_quantity,
                NULL, -- scale_factor,
                NULL, -- adjusted_orders,
                NULL, -- total_ordered,
                NULL, -- total_adjusted,
                EXTRACT(EPOCH FROM(CLOCK_TIMESTAMP() - startTime)) * 1000 -- time_taken_ms
            );

        RETURN QUERY SELECT * FROM adjusted_orders;
        DROP TABLE IF EXISTS valid_orders, adjusted_orders, final_orders, origin_orders;
        RETURN;
    END IF;

    -- Calculate target total quantity considering total_adjusted if available
    targetTotalQuantity := COALESCE(offerRecord.total_adjusted, ROUND(totalOrderedQuantity / unitTotalSize) * unitTotalSize);

    -- Calculate scaling factor
    scaleFactor := targetTotalQuantity / totalOrderedQuantity;

    -- Initial adjustment of order quantities
    INSERT INTO adjusted_orders
    SELECT * FROM valid_orders;

    FOR orderRecord IN SELECT * FROM valid_orders LOOP
        IF NOT orderRecord.quantity_adjusted_locked THEN
            adjustedQuantity := orderRecord.quantity * scaleFactor;
            adjustedQuantity := ROUND(adjustedQuantity / roundingStepSize) * roundingStepSize;
            adjustedQuantity := GREATEST(0, adjustedQuantity);
            UPDATE adjusted_orders
            SET quantity_adjusted = adjustedQuantity
            WHERE adjusted_orders.id = orderRecord.id;
        END IF;
    END LOOP;

    -- Calculate total quantity of adjusted orders
    SELECT SUM(COALESCE(adjusted_orders.quantity_adjusted, 0))
    INTO currentTotalAdjusted
    FROM adjusted_orders;

    -- Calculate the remaining difference
    remainingDifference := targetTotalQuantity - currentTotalAdjusted;

    -- Get the count of non-locked orders
    SELECT COUNT(*) INTO nonLockedOrderCount FROM adjusted_orders WHERE NOT adjusted_orders.quantity_adjusted_locked;

    -- Remaining diff is larger than 0 and has not locked orders
    IF remainingDifference <> 0 AND nonLockedOrderCount > 0 THEN
        remainingDiffStep := roundingStepSize * SIGN(remainingDifference);
        remainingDiffSteps := ROUND(ABS(remainingDifference) / roundingStepSize);

        -- Distribute the remaining difference across non-locked orders
        FOR remainingDiffPos IN 0..(remainingDiffSteps - 1) LOOP
            UPDATE adjusted_orders
            SET quantity_adjusted = adjusted_orders.quantity_adjusted + remainingDiffStep
            WHERE adjusted_orders.id = (SELECT adjusted_orders.id FROM adjusted_orders WHERE NOT adjusted_orders.quantity_adjusted_locked OFFSET remainingDiffPos % nonLockedOrderCount LIMIT 1);
        END LOOP;

        -- Calculate the index for the next non-locked order
        remainingDiffPos := CASE
            WHEN nonLockedOrderCount > (remainingDiffPos % nonLockedOrderCount) - 1 THEN 0
            ELSE remainingDiffPos + 1
        END;

        -- Recalculate the remaining difference
        SELECT targetTotalQuantity - SUM(COALESCE(adjusted_orders.quantity_adjusted, 0))
        INTO remainingDifference
        FROM adjusted_orders;

        -- Adjust the first non-locked order if there is still a remaining difference
        IF remainingDifference <> 0 THEN
            UPDATE adjusted_orders
            SET quantity_adjusted = adjusted_orders.quantity_adjusted + remainingDifference
            WHERE adjusted_orders.id = (SELECT adjusted_orders.id FROM adjusted_orders WHERE NOT adjusted_orders.quantity_adjusted_locked OFFSET remainingDiffPos LIMIT 1);
        END IF;
    END IF;

    -- Create a temporary table for final orders
    CREATE TEMP TABLE final_orders AS
    SELECT
        distributions_orders.id,
        distributions_orders.distributions_offer,
        distributions_orders.basket,
        distributions_orders.quantity,
        distributions_orders.quantity_adjusted,
        distributions_orders.quantity_adjusted_locked,
        distributions_orders.rounding_error
    FROM distributions_orders
    WHERE distributions_orders.distributions_offer = distr_off_id;

    -- Set final_orders with the adjusted values from adjusted_orders
    FOR finalOrder IN SELECT * FROM final_orders LOOP
        IF finalOrder.quantity = 0 THEN
            UPDATE final_orders
            SET quantity_adjusted = finalOrder.quantity
            WHERE final_orders.id = finalOrder.id;
        ELSE
            SELECT *
            INTO adjustedOrder
            FROM adjusted_orders
            WHERE adjusted_orders.id = finalOrder.id;

            IF (adjustedOrder.quantity_adjusted IS NOT NULL AND adjustedOrder.quantity_adjusted < 0) THEN
                debugMsgs := COALESCE(debugMsgs, '[]'::jsonb) || jsonb_build_array('Warning: Adjusted order id ' || adjustedOrder.id || ' is below zero (' || adjustedOrder.quantity_adjusted || ').');
                UPDATE final_orders
                SET quantity_adjusted = adjustedOrder.quantity_adjusted, rounding_error = 'quantity_adjusted_below_zero'
                WHERE final_orders.id = finalOrder.id;
            ELSE
                UPDATE final_orders
                SET quantity_adjusted = COALESCE(adjustedOrder.quantity_adjusted, 0)
                WHERE final_orders.id = finalOrder.id;
            END IF;
        END IF;
    END LOOP;

    -- Calculate total ordered quantity
    SELECT SUM(COALESCE(distributions_orders.quantity, 0))
    INTO finalTotalOrderedQuantity
    FROM distributions_orders
    WHERE distributions_orders.distributions_offer = distr_off_id;

    -- Calculate total adjusted quantity
    SELECT SUM(COALESCE(final_orders.quantity_adjusted, 0))
    INTO finalTotalAdjustedQuantity
    FROM final_orders;

    debugFinalOrders := (SELECT json_agg(row_to_json(final_orders)) FROM final_orders);

    INSERT INTO distributions_orders_rounding
    (
        distributions_offer,
        messages,
        origin_offer,
        origin_orders,
        remain_diff,
        target_total_quantity,
        scale_factor,
        adjusted_orders,
        total_ordered,
        total_adjusted,
        time_taken_ms
    )
    VALUES (
        distr_off_id, -- distributions_offer,
        debugMsgs, -- messages,
        debugOriginOffer, -- origin_offer,
        debugOriginOrders, -- origin_orders,
        remainingDifference, -- remain_diff,
        targetTotalQuantity, -- target_total_quantity,
        scaleFactor, -- scale_factor,
        debugFinalOrders, -- adjusted_orders,
        finalTotalOrderedQuantity, -- total_ordered,
        finalTotalAdjustedQuantity, -- total_adjusted,
        EXTRACT(EPOCH FROM(CLOCK_TIMESTAMP() - startTime)) * 1000 -- time_taken_ms
    );

    RETURN QUERY SELECT * FROM final_orders;
    DROP TABLE IF EXISTS adjusted_orders, valid_orders, final_orders, origin_orders;
    RETURN;
END;
$$;

SELECT kp__rounding_orders(12532);
SELECT kp__rounding_orders(1);

SELECT * FROM distributions_orders ORDER BY id DESC LIMIT 100;

SELECT total, total_adjusted, cloned_offer->>'step_size' AS step_size, cloned_offer->>'rounding_step_size' AS rounding_step_size FROM distributions_offers WHERE id = 12532;

UPDATE distributions_offers SET total_adjusted = NULL WHERE id = 12532;
UPDATE distributions_offers SET total_adjusted = 20.0 WHERE id = 12532;
