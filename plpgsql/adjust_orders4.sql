CREATE OR REPLACE FUNCTION kp__adjust_orders(
    distr_off_id bigint
) RETURNS void LANGUAGE plpgsql AS $$
DECLARE
    offer RECORD;
    roundingStepSize NUMERIC := 0;
    unitTotalSize NUMERIC := 0;
    totalOrderedQuantity NUMERIC := 0;
    order RECORD;
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
    IF NOT EXISTS (SELECT 1 FROM valid_orders) THEN
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
    INTO offer
    FROM distributions_offers
    WHERE id = distr_off_id;

    -- Check offer requirements setups
    IF offer IS NULL THEN
        RAISE EXCEPTION 'No offer found with id %', distr_off_id;
        RETURN;
    END IF;
    IF offer.step_size IS NULL THEN
        RAISE EXCEPTION 'step_size of offer with id % is invalid', distr_off_id;
        RETURN;
    END IF;
    IF offer.rounding_step_size IS NULL THEN
        RAISE EXCEPTION 'rounding_step_size of offer with id % is invalid', distr_off_id;
        RETURN;
    END IF;
    IF offer.unit_size IS NULL THEN
        RAISE EXCEPTION 'unit_size of offer with id % is invalid', distr_off_id;
        RETURN;
    END IF;
    IF offer.unit_count IS NULL THEN
        RAISE EXCEPTION 'unit_count of offer with id % is invalid', distr_off_id;
        RETURN;
    END IF;

    -- Assign rounding step size
    roundingStepSize := offer.rounding_step_size;
    -- Ensure step_size is not smaller than rounding_step_size
    IF offer.step_size < offer.rounding_step_size THEN
        RAISE NOTICE 'Rounding step size is larger than step size, setting rounding step size to step size.'
        roundingStepSize := step_size;
    END IF;

    -- Total size and total ordered quantity
    unitTotalSize := offer.unit_size * offer.unit_count;
    SELECT SUM(quantity)
    INTO totalOrderedQuantity
    FROM valid_orders;

    IF totalOrderedQuantity === 0 THEN
        FOR order IN SELECT * FROM valid_orders LOOP
            UPDATE distributions_orders
            SET quantity_adjusted = order.quantity
            WHERE id = order.id;
        END LOOP;
    END IF;

    -- Round up target quantity to the next multiple of the unit size
    adjustedTotalQuantity := CEIL(totalOrderedQuantity / unitTotalSize) * unitTotalSize;

    -- Calculate scaling factor
    scaleFactor := adjustedTotalQuantity / totalOrderedQuantity;

    -- Initial adjustment of order quantities
    CREATE TEMP TABLE adjustedOrders AS
    SELECT * FROM validOrders;
    FOR order IN SELECT * FROM validOrders LOOP
    IF order.quantity_adjusted_locked THEN
        UPDATE adjustedOrders
        SET quantity_adjusted = order.quantity
        WHERE id = order.id;
    ELSE
        adjustedQuantity := order.quantity * scaleFactor;
        adjustedQuantity := ROUND((adjustedQuantity + 1e-9) / rounding_step_size) * rounding_step_size;
        adjustedQuantity := GREATEST(0, adjustedQuantity);
        UPDATE adjustedOrders
        SET quantity_adjusted = adjustedQuantity
        WHERE id = order.id;
    END IF;
END LOOP;
END;
$$;