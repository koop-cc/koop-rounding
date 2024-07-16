CREATE OR REPLACE FUNCTION kp__adjust_orders(
    distr_off_id bigint,
    debug BOOL
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
    nonLockedOrderRecord RECORD;
    nonLockedOrderCount INTEGER;
    remainingDiffStep NUMERIC;
    remainingDiffSteps INTEGER;
    remainingDiffPos INTEGER;
BEGIN
    -- Select all distributions orders
    -- create a temporary table. Table is automatically destroyed after leaving
    -- function
    CREATE TEMP TABLE orders AS
    SELECT
        distributions_orders."id",
        distributions_orders.quantity,
        distributions_orders.quantity_adjusted,
        distributions_orders.quantity_adjusted_locked
        FROM distributions_orders
        -- Filter out orders with quantity 0
        WHERE distributions_offer = distr_off_id;
    IF NOT EXISTS (SELECT 1 FROM orders) THEN
        RAISE EXCEPTION 'No distributions orders found for offer id %', distr_off_id;
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

        -- Select all valid distributions orders without quantity 0
    CREATE TEMP TABLE validOrders AS
    SELECT
        distributions_orders."id",
        distributions_orders.quantity,
        distributions_orders.quantity_adjusted,
        distributions_orders.quantity_adjusted_locked
        FROM distributions_orders
        -- Filter out orders with quantity 0
        WHERE distributions_offer = distr_off_id AND quantity <> 0;
    IF NOT EXISTS (SELECT 1 FROM validOrders) THEN
        RAISE EXCEPTION 'No distributions orders found for offer id %', distr_off_id;
        RETURN;
    END IF;

    IF debug THEN
        RAISE NOTICE 'Valid Orders: %', (SELECT array_agg(row_to_json(validOrders)) FROM validOrders);
    END IF;

    -- Total size and total ordered quantity
    unitTotalSize := offerRecord.unit_size * offerRecord.unit_count;

    -- Calculate total ordered quantity considering adjusted quantity if available
    SELECT COALESCE(SUM(COALESCE(quantity_adjusted, quantity)), 0)
    INTO totalOrderedQuantity
    FROM validOrders;

    IF totalOrderedQuantity = 0 THEN
        RAISE NOTICE 'Total ordered quantity is 0, exit function.'
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
    remainingDifference := adjustedTotalQuantity - currentTotalAdjusted;
    IF debug THEN
        RAISE NOTICE 'Remaining difference: %', remainingDifference;
    END IF;

    -- Create a temporary table for non-locked orders
    CREATE TEMP TABLE nonLockedOrders AS
    SELECT *
    FROM adjustedOrders
    WHERE NOT quantity_adjusted_locked;

    -- Get the count of non-locked orders
    SELECT COUNT(*) INTO nonLockedOrderCount FROM nonLockedOrders;

    -- Remaining diff is larger than 0 and has not locked orders
    IF remainingDifference <> 0 AND nonLockedOrderCount > 0 THEN
        remainingDiffStep := roundingStepSize * SIGN(remainingDifference);
        remainingDiffSteps := ROUND(ABS(remainingDifference) / roundingStepSize);

        -- Distribute the remaining difference across non-locked orders
        FOR remainingDiffPos IN 0..(remainingDiffSteps - 1) LOOP
            UPDATE nonLockedOrders
            SET quantity_adjusted = quantity_adjusted + remainingDiffStep
            WHERE id = (SELECT id FROM nonLockedOrders OFFSET remainingDiffPos % nonLockedOrderCount LIMIT 1);
        END LOOP;

        -- Calculate the index for the next non-locked order
        remainingDiffPos := CASE
            WHEN nonLockedOrderCount > (remainingDiffPos % nonLockedOrderCount) - 1 THEN 0
            ELSE remainingDiffPos + 1
        END;

        -- Recalculate the remaining difference
        SELECT adjustedTotalQuantity - SUM(COALESCE(quantity_adjusted, 0))
        INTO remainingDifference
        FROM adjustedOrders;

        -- Adjust the first non-locked order if there is still a remaining difference
        IF remainingDifference <> 0 THEN
            UPDATE nonLockedOrders
            SET quantity_adjusted = quantity_adjusted + remainingDifference
            WHERE id = (SELECT id FROM nonLockedOrders OFFSET remainingDiffPos LIMIT 1);
        END IF;
    END IF;

END;
$$;