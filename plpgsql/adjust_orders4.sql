CREATE OR REPLACE FUNCTION kp__adjust_orders(
    distr_off_id bigint
) RETURNS void LANGUAGE plpgsql AS $$
DECLARE
    offerRecord RECORD;
    roundingStepSize NUMERIC := 0;
    unitTotalSize NUMERIC := 0;
    totalOrderedQuantity NUMERIC := 0;
    orderRecord RECORD;
    adjustedTotalQuantity NUMERIC;
    scaleFactor NUMERIC;
    adjustedQuantity NUMERIC;
BEGIN
    -- Select all valid distributions orders without quantity 0 and
    -- create a temporary table. Table is automatically destroyed after leaving
    -- function
    CREATE TEMP TABLE validOrders AS
    SELECT
        distributions_orders."id",
        distributions_orders.quantity,
        distributions_orders.quantity_adjusted,
        distributions_orders.quantity_adjusted_locked
        FROM distributions_orders
        WHERE distributions_offer = distr_off_id AND quantity <> 0;
    IF NOT EXISTS (SELECT 1 FROM validOrders) THEN
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
    SELECT SUM(quantity)
    INTO totalOrderedQuantity
    FROM validOrders;

    IF totalOrderedQuantity = 0 THEN
        FOR orderRecord IN SELECT * FROM validOrders LOOP
            UPDATE distributions_orders
            SET quantity_adjusted = orderRecord.quantity
            WHERE id = orderRecord.id;
        END LOOP;
        RETURN; -- Exit the function here if totalOrderedQuantity is 0
    END IF;

    -- Round up target quantity to the next multiple of the unit size
    adjustedTotalQuantity := CEIL(totalOrderedQuantity / unitTotalSize) * unitTotalSize;

    -- Calculate scaling factor
    scaleFactor := adjustedTotalQuantity / totalOrderedQuantity;

    -- Initial adjustment of order quantities
    CREATE TEMP TABLE adjustedOrders AS
    SELECT * FROM validOrders;

    FOR orderRecord IN SELECT * FROM validOrders LOOP
        IF orderRecord.quantity_adjusted_locked THEN
            UPDATE adjustedOrders
            SET quantity_adjusted = orderRecord.quantity
            WHERE id = orderRecord.id;
        ELSE
            adjustedQuantity := orderRecord.quantity * scaleFactor;
            adjustedQuantity := ROUND((adjustedQuantity + 1e-9) / roundingStepSize) * roundingStepSize;
            adjustedQuantity := GREATEST(0, adjustedQuantity);
            UPDATE adjustedOrders
            SET quantity_adjusted = adjustedQuantity
            WHERE id = orderRecord.id;
        END IF;
    END LOOP;
END;
$$;