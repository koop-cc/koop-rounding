DROP FUNCTION IF EXISTS kp__adjust_orders(bigint, BOOL, BOOL);

CREATE OR REPLACE FUNCTION kp__adjust_orders(
    distr_off_id bigint,
    debug BOOL,
    updateorders BOOL
) RETURNS TABLE(level TEXT, message TEXT, data JSONB) LANGUAGE plpgsql AS $$
DECLARE
    errorMsg TEXT;
    debugOffer JSONB;
    debugOriginOrders JSONB;
    debugFinalOrders JSONB;
    debugTotalOrderedQuantity JSONB;
    debugTotalAdjustedQuantity JSONB;
    debugTimeTaken JSONB;
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
    endTime TIMESTAMP;
    timeDiff INTERVAL;
    finalTotalOrderedQuantity NUMERIC;
    finalTotalAdjustedQuantity NUMERIC;
BEGIN
    -- Start time
    startTime := CLOCK_TIMESTAMP();

    -- Create temporary table for debug output
    CREATE TEMP TABLE debug_output(level TEXT, message TEXT, data JSONB);

    -- Select all valid distributions orders without quantity 0 and create a temporary table
    CREATE TEMP TABLE validOrders AS
    SELECT
        "id",
        quantity,
        quantity_adjusted,
        quantity_adjusted_locked
    FROM distributions_orders
    WHERE distributions_offer = distr_off_id AND quantity <> 0;

    IF NOT EXISTS (SELECT 1 FROM validOrders) THEN
        errorMsg := 'No distributions orders with quantity larger than 0 found for offer id ' || distr_off_id;
        RAISE INFO '%', errorMsg;
        INSERT INTO debug_output (level, message, data) VALUES ('error', errorMsg, NULL);
        RETURN QUERY SELECT * FROM debug_output;
        RETURN;
    END IF;

    -- Select the distribution offer details
    SELECT
        (cloned_offer->>'unit_count')::NUMERIC AS unit_count,
        (cloned_offer->>'unit_size')::NUMERIC AS unit_size,
        (cloned_offer->>'step_size')::NUMERIC AS step_size,
        (cloned_offer->>'rounding_step_size')::NUMERIC AS rounding_step_size,
        total_adjusted
    INTO offerRecord
    FROM distributions_offers
    WHERE id = distr_off_id;

    debugOffer := row_to_json(offerRecord);
    IF debug THEN
        RAISE INFO 'Origin Offer: %', debugOffer;
    END IF;
    INSERT INTO debug_output (level, message, data) VALUES ('info', 'originOffer', debugOffer);

    -- Check offer requirements setups
    IF offerRecord IS NULL THEN
        errorMsg := 'No offer found with id ' || distr_off_id;
        RAISE NOTICE '%', errorMsg;
        INSERT INTO debug_output (level, message, data) VALUES ('error', errorMsg, NULL);
        RETURN QUERY SELECT * FROM debug_output;
        RETURN;
    END IF;
    IF offerRecord.step_size IS NULL THEN
        errorMsg := 'step_size of offer with id ' || distr_off_id || ' is invalid';
        RAISE NOTICE '%', errorMsg;
        INSERT INTO debug_output (level, message, data) VALUES ('error', errorMsg, NULL);
        RETURN QUERY SELECT * FROM debug_output;
        RETURN;
    END IF;
    IF offerRecord.rounding_step_size IS NULL THEN
        errorMsg := 'rounding_step_size of offer with id ' || distr_off_id || ' is invalid';
        RAISE NOTICE '%', errorMsg;
        INSERT INTO debug_output (level, message, data) VALUES ('error', errorMsg, NULL);
        RETURN QUERY SELECT * FROM debug_output;
        RETURN;
    END IF;
    IF offerRecord.unit_size IS NULL THEN
        errorMsg := 'unit_size of offer with id ' || distr_off_id || ' is invalid';
        RAISE NOTICE '%', errorMsg;
        INSERT INTO debug_output (level, message, data) VALUES ('error', errorMsg, NULL);
        RETURN QUERY SELECT * FROM debug_output;
        RETURN;
    END IF;
    IF offerRecord.unit_count IS NULL THEN
        errorMsg := 'unit_count of offer with id ' || distr_off_id || ' is invalid';
        RAISE NOTICE '%', errorMsg;
        INSERT INTO debug_output (level, message, data) VALUES ('error', errorMsg, NULL);
        RETURN QUERY SELECT * FROM debug_output;
        RETURN;
    END IF;

    -- Assign rounding step size
    roundingStepSize := offerRecord.rounding_step_size;

    -- Ensure step_size is not smaller than rounding_step_size
    IF offerRecord.step_size < offerRecord.rounding_step_size THEN
        errorMsg := 'Rounding step size is larger than step size, setting rounding step size to step size.';
        RAISE WARNING '%', errorMsg;
        INSERT INTO debug_output (level, message, data) VALUES ('warning', errorMsg, NULL);
        roundingStepSize := offerRecord.step_size;
    END IF;

    -- Total size and total ordered quantity
    unitTotalSize := offerRecord.unit_size * offerRecord.unit_count;

    -- Calculate total ordered quantity considering adjusted quantity if available
    SELECT COALESCE(SUM(COALESCE(quantity_adjusted, quantity)), 0)
    INTO totalOrderedQuantity
    FROM validOrders;

    IF totalOrderedQuantity = 0 THEN
        errorMsg := 'Total ordered quantity is 0, exit function.';
        RAISE NOTICE '%', errorMsg;
        INSERT INTO debug_output (level, message, data) VALUES ('error', errorMsg, NULL);
        RETURN QUERY SELECT * FROM debug_output;
        RETURN;
    END IF;

    -- Calculate target total quantity considering total_amount_adjusted if available
    targetTotalQuantity := COALESCE(offerRecord.total_adjusted, ROUND(totalOrderedQuantity / unitTotalSize) * unitTotalSize);
    IF debug THEN
        errorMsg := 'Target Total Adjusted Quantity: ' || targetTotalQuantity;
        RAISE INFO '%', errorMsg;
        INSERT INTO debug_output (level, message, data) VALUES ('info', 'targetTotalAdjustedQuantity', to_jsonb(targetTotalQuantity));
    END IF;

    -- Calculate scaling factor
    scaleFactor := targetTotalQuantity / totalOrderedQuantity;
    IF debug THEN
        errorMsg := 'Scale factor ' || scaleFactor;
        RAISE INFO '%', errorMsg;
        INSERT INTO debug_output (level, message, data) VALUES ('info', 'scaleFactor', to_jsonb(scaleFactor));
    END IF;

    -- Initial adjustment of order quantities
    CREATE TEMP TABLE adjustedOrders AS
    SELECT * FROM validOrders;

    FOR orderRecord IN SELECT * FROM validOrders LOOP
        IF NOT orderRecord.quantity_adjusted_locked THEN
            adjustedQuantity := orderRecord.quantity * scaleFactor;
            adjustedQuantity := ROUND(adjustedQuantity / roundingStepSize, 3) * roundingStepSize;
            adjustedQuantity := GREATEST(0, adjustedQuantity);
            UPDATE adjustedOrders
            SET quantity_adjusted = adjustedQuantity
            WHERE id = orderRecord.id;
        END IF;
    END LOOP;

    -- Calculate total quantity of adjusted orders
    SELECT SUM(COALESCE(quantity_adjusted, 0))
    INTO currentTotalAdjusted
    FROM adjustedOrders;

    -- Calculate the remaining difference
    remainingDifference := targetTotalQuantity - currentTotalAdjusted;
    IF debug THEN
        errorMsg := 'Remaining difference: ' || remainingDifference;
        RAISE INFO '%', errorMsg;
        INSERT INTO debug_output (level, message, data) VALUES ('info', 'remainingDifference', to_jsonb(remainingDifference));
    END IF;

    -- Get the count of non-locked orders
    SELECT COUNT(*) INTO nonLockedOrderCount FROM adjustedOrders WHERE NOT quantity_adjusted_locked;

    -- Remaining diff is larger than 0 and has not locked orders
    IF remainingDifference <> 0 AND nonLockedOrderCount > 0 THEN
        remainingDiffStep := roundingStepSize * SIGN(remainingDifference);
        remainingDiffSteps := ROUND(ABS(remainingDifference) / roundingStepSize, 3);

        -- Distribute the remaining difference across non-locked orders
        FOR remainingDiffPos IN 0..(remainingDiffSteps - 1) LOOP
            UPDATE adjustedOrders
            SET quantity_adjusted = quantity_adjusted + remainingDiffStep
            WHERE id = (SELECT id FROM adjustedOrders WHERE NOT quantity_adjusted_locked OFFSET remainingDiffPos % nonLockedOrderCount LIMIT 1);
        END LOOP;

        -- Calculate the index for the next non-locked order
        remainingDiffPos := CASE
            WHEN nonLockedOrderCount > (remainingDiffPos % nonLockedOrderCount) - 1 THEN 0
            ELSE remainingDiffPos + 1
        END;

        -- Recalculate the remaining difference
        SELECT targetTotalQuantity - SUM(COALESCE(quantity_adjusted, 0))
        INTO remainingDifference
        FROM adjustedOrders;

        -- Adjust the first non-locked order if there is still a remaining difference
        IF remainingDifference <> 0 THEN
            UPDATE adjustedOrders
            SET quantity_adjusted = quantity_adjusted + remainingDifference
            WHERE id = (SELECT id FROM adjustedOrders WHERE NOT quantity_adjusted_locked OFFSET remainingDiffPos LIMIT 1);
        END IF;
    END IF;

    -- Create a temporary table for final orders
    CREATE TEMP TABLE finalOrders AS
    SELECT
        "id",
        quantity,
        quantity_adjusted,
        quantity_adjusted_locked,
        rounding_error
    FROM distributions_orders
    WHERE distributions_offer = distr_off_id;
    -- Set finalOrders with the adjusted values from adjustedOrders
    FOR finalOrder IN SELECT * FROM finalOrders LOOP
        IF finalOrder.quantity = 0 THEN
            UPDATE finalOrders
            SET quantity_adjusted = finalOrder.quantity
            WHERE id = finalOrder.id;
        ELSE
            SELECT *
            INTO adjustedOrder
            FROM adjustedOrders
            WHERE id = finalOrder.id;

            IF (adjustedOrder.quantity_adjusted IS NOT NULL AND adjustedOrder.quantity_adjusted < 0) THEN
                errorMsg := 'Adjusted order id ' || adjustedOrder.id || ' is below zero (' || adjustedOrder.quantity_adjusted || ').';
                RAISE WARNING '%', errorMsg;
                INSERT INTO debug_output (level, message, data) VALUES ('error', 'roundingError', to_jsonb(errorMsg));
                UPDATE finalOrders
                SET quantity_adjusted = adjustedOrder.quantity_adjusted, rounding_error = 'quantity_adjusted_below_zero'
                WHERE id = finalOrder.id;
            ELSE
                UPDATE finalOrders
                SET quantity_adjusted = COALESCE(adjustedOrder.quantity_adjusted, 0)
                WHERE id = finalOrder.id;
            END IF;
        END IF;
    END LOOP;

    -- Select all distributions orders before updating
    CREATE TEMP TABLE originOrders AS
    SELECT
        "id",
        quantity,
        quantity_adjusted,
        quantity_adjusted_locked,
        rounding_error
    FROM distributions_orders
    WHERE distributions_offer = distr_off_id;

    -- Update distributions_orders with finalOrders
    IF updateorders THEN
        FOR finalOrder IN SELECT * FROM finalOrders LOOP
            UPDATE distributions_orders
            SET quantity_adjusted = finalOrder.quantity_adjusted,
                rounding_error = finalOrder.rounding_error
            WHERE id = finalOrder.id;
        END LOOP;
    END IF;

    -- Calculate total ordered quantity
    SELECT SUM(COALESCE(quantity, 0))
    INTO finalTotalOrderedQuantity
    FROM distributions_orders
    WHERE distributions_offer = distr_off_id;

    -- Calculate total adjusted quantity
    SELECT SUM(COALESCE(quantity_adjusted, 0))
    INTO finalTotalAdjustedQuantity
    FROM finalOrders;

    -- End time
    endTime := CLOCK_TIMESTAMP();
    timeDiff := endTime - startTime;

    debugOriginOrders := (SELECT json_agg(row_to_json(originOrders)) FROM originOrders);
    debugFinalOrders := (SELECT json_agg(row_to_json(finalOrders)) FROM finalOrders);
    debugTotalOrderedQuantity := to_jsonb(finalTotalOrderedQuantity);
    debugTotalAdjustedQuantity := to_jsonb(finalTotalAdjustedQuantity);
    debugTimeTaken := to_jsonb(EXTRACT(EPOCH FROM timeDiff) * 1000);

    -- Debugging output
    IF debug THEN
        RAISE INFO 'Origin: %', debugOriginOrders;
        RAISE INFO 'Adjusted: %', debugFinalOrders;
        RAISE INFO 'Total ordered: %', finalTotalOrderedQuantity;
        RAISE INFO 'Total adjusted: %', finalTotalAdjustedQuantity;
        RAISE INFO 'Time taken: % milliseconds', debugTimeTaken;
    END IF;

    INSERT INTO debug_output (level, message, data) VALUES ('info', 'originOrders', debugOriginOrders);
    INSERT INTO debug_output (level, message, data) VALUES ('info', 'adjustedOrders', debugFinalOrders);
    INSERT INTO debug_output (level, message, data) VALUES ('info', 'totalOrdered', debugTotalOrderedQuantity);
    INSERT INTO debug_output (level, message, data) VALUES ('info', 'totalAdjusted', debugTotalAdjustedQuantity);
    INSERT INTO debug_output (level, message, data) VALUES ('info', 'timeTakenMs', debugTimeTaken);

    -- Return debug data
    RETURN QUERY SELECT * FROM debug_output;
END;
$$;

SELECT * FROM distributions_orders ORDER BY id DESC LIMIT 100;

SELECT total, total_adjusted FROM distributions_offers WHERE id = 13372;

UPDATE distributions_offers SET total_adjusted = NULL WHERE id = 13372;
UPDATE distributions_offers SET total_adjusted = 20.0 WHERE id = 13372;

SELECT kp__adjust_orders(12, TRUE, FALSE);