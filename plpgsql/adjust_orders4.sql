CREATE OR REPLACE FUNCTION kp__adjust_orders(
    distr_off_id bigint,
    debug BOOL,
    updateOrders BOOL
) RETURNS void LANGUAGE plpgsql AS $$
DECLARE
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
        RAISE EXCEPTION 'No distributions orders with quantity larger than 0 found for offer id %', distr_off_id;
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

    IF debug THEN
        RAISE NOTICE 'Offer: %', row_to_json(offerRecord);
    END IF;

    -- Check offer requirements setups
    IF offerRecord IS NULL THEN
        RAISE EXCEPTION 'No offer found with id %', distr_off_id;
        RETURN;
    END IF;
    IF offerRecord.step_size IS NULL THEN
        RAISE EXCEPTION 'step_size of offer with id % is invalid', distr_off_id;
        RETURN;
    END IF;
    IF offerRecord.rounding_step_size IS NULL THEN
        RAISE EXCEPTION 'rounding_step_size of offer with id % is invalid', distr_off_id;
        RETURN;
    END IF;
    IF offerRecord.unit_size IS NULL THEN
        RAISE EXCEPTION 'unit_size of offer with id % is invalid', distr_off_id;
        RETURN;
    END IF;
    IF offerRecord.unit_count IS NULL THEN
        RAISE EXCEPTION 'unit_count of offer with id % is invalid', distr_off_id;
        RETURN;
    END IF;

    -- Assign rounding step size
    roundingStepSize := offerRecord.rounding_step_size;

    -- Ensure step_size is not smaller than rounding_step_size
    IF offerRecord.step_size < offerRecord.rounding_step_size THEN
        RAISE NOTICE 'Rounding step size is larger than step size, setting rounding step size to step size.';
        roundingStepSize := offerRecord.step_size;
    END IF;

    -- Total size and total ordered quantity
    unitTotalSize := offerRecord.unit_size * offerRecord.unit_count;

    -- Calculate total ordered quantity considering adjusted quantity if available
    SELECT COALESCE(SUM(COALESCE(quantity_adjusted, quantity)), 0)
    INTO totalOrderedQuantity
    FROM validOrders;

    IF totalOrderedQuantity = 0 THEN
        RAISE NOTICE 'Total ordered quantity is 0, exit function.';
        RETURN; -- Exit the function here if totalOrderedQuantity is 0
    END IF;

    -- Calculate target total quantity considering total_amount_adjusted if available
    targetTotalQuantity := COALESCE(offerRecord.total_adjusted, ROUND(totalOrderedQuantity / unitTotalSize) * unitTotalSize);
    IF debug THEN
        RAISE NOTICE 'Target Total Adjusted Quantity: %', targetTotalQuantity;
    END IF;

    -- Calculate scaling factor
    scaleFactor := targetTotalQuantity / totalOrderedQuantity;
    IF debug THEN
        RAISE NOTICE 'Scale factor: %', scaleFactor;
    END IF;

    -- Initial adjustment of order quantities
    CREATE TEMP TABLE adjustedOrders AS
    SELECT * FROM validOrders;

    FOR orderRecord IN SELECT * FROM validOrders LOOP
        IF NOT orderRecord.quantity_adjusted_locked THEN
            adjustedQuantity := orderRecord.quantity * scaleFactor;
            adjustedQuantity := ROUND(adjustedQuantity / roundingStepSize) * roundingStepSize;
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
        RAISE NOTICE 'Remaining difference: %', remainingDifference;
    END IF;

    -- Get the count of non-locked orders
    SELECT COUNT(*) INTO nonLockedOrderCount FROM adjustedOrders WHERE NOT quantity_adjusted_locked;

    -- Remaining diff is larger than 0 and has not locked orders
    IF remainingDifference <> 0 AND nonLockedOrderCount > 0 THEN
        remainingDiffStep := roundingStepSize * SIGN(remainingDifference);
        remainingDiffSteps := ROUND(ABS(remainingDifference) / roundingStepSize);

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
    FOR finalOrder IN SELECT * FROM orders LOOP
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
                RAISE WARNING 'Adjusted order id % is below zero (%).', adjustedOrder.id, adjustedOrder.quantity_adjusted;
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

    -- Update distributions_orders with finalOrders
    IF updateOrders THEN
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
    FROM distributions_orders
    WHERE distributions_offer = distr_off_id;

    -- End time
    endTime := CLOCK_TIMESTAMP();
    timeDiff := endTime - startTime;

    -- Debugging output
    IF debug THEN
        RAISE NOTICE 'Output: %', (SELECT array_agg(row_to_json(finalOrders)) FROM finalOrders);
        RAISE NOTICE 'Ordered: %', finalTotalOrderedQuantity;
        RAISE NOTICE 'Adjusted: %', finalTotalAdjustedQuantity;
        RAISE NOTICE 'Time taken: % milliseconds', EXTRACT(EPOCH FROM timeDiff) * 1000;
    END IF;

END;
$$;