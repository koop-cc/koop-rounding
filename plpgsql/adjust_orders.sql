CREATE OR REPLACE FUNCTION kp__adjust_orders(
    distr_off_id bigint
) RETURNS void LANGUAGE plpgsql AS $$
DECLARE
	offer RECORD;
    valid_order RECORD;
    step_size NUMERIC := 0;
    rounding_step_size NUMERIC := 0;
    total_ordered_quantity NUMERIC := 0;
    unit_total_size NUMERIC := 0;
    adjusted_total_quantity NUMERIC := 0;
    scale_factor NUMERIC := 1;
    current_total_adjusted NUMERIC := 0;
    remaining_difference NUMERIC;
    order_count INT := 0;
    adjusted_orders RECORD;
    single_order RECORD;
    adjusted_quantity NUMERIC := 0;
    step NUMERIC := 0;
    steps INT := 0;
    i INT := 0;
    order_index INT := 0;
    current_adjusted_order RECORD;
BEGIN
    -- Select all valid distributions orders without quantity 0 and
    -- create a temporary table. Table is automatically destroyed after leaving
    -- function
    CREATE TEMP TABLE valid_orders AS
	SELECT
        *
        FROM distributions_orders
        WHERE distributions_offer = distr_off_id AND quantity <> 0 ;
	IF NOT EXISTS (SELECT 1 FROM valid_orders) THEN
        RAISE EXCEPTION 'No distributions orders found for offer id %', distr_off_id;
        RETURN;
    END IF;

    -- Select the distribution offer details
	SELECT
        (cloned_offer->>'step_size')::NUMERIC AS step_size,
        (cloned_offer->>'rounding_step_size')::NUMERIC AS rounding_step_size,
        (cloned_offer->>'unit_size')::NUMERIC AS unit_size,
        (cloned_offer->>'unit_count')::NUMERIC AS unit_count
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

    -- Assign step sizes
    step_size := offer.step_size;
    rounding_step_size := offer.rounding_step_size;

    -- Ensure step_size is not smaller than rounding_step_size
    IF step_size < rounding_step_size THEN
        RAISE WARNING 'Rounding step size is larger than step size, setting rounding step size to step size.';
        rounding_step_size := step_size;
    END IF;

    -- Total size of the offer Menge * Anzahl
    unit_total_size := offer.unit_size * offer.unit_count;
    total_ordered_quantity := 0;

    -- Setup initial values
    FOR valid_order IN SELECT * FROM valid_orders
    LOOP
        -- Calculate the total ordered quantity
        total_ordered_quantity := total_ordered_quantity + valid_order.quantity;
        -- Copy the original quantity to quantity_adjusted
        valid_order.quantity_adjusted := valid_order.quantity;
    END LOOP;

    -- RAISE EXCEPTION 'total_ordered_quantity %', total_ordered_quantity ;

    -- Round up target quantity to the next multiple of the unit size
    adjusted_total_quantity := CEIL(total_ordered_quantity / unit_total_size) * unit_total_size;

    -- Calculate scaling factor
    scale_factor := adjusted_total_quantity / total_ordered_quantity;

    -- Adjust order quantities for none locked entries
    FOR valid_order IN SELECT * FROM valid_orders
    LOOP
        IF NOT valid_order.locked THEN
            valid_order.adjusted_quantity := ROUND(valid_order.quantity * scale_factor / rounding_step_size) * rounding_step_size;
            valid_order.adjusted_quantity := GREATEST(0, valid_order.adjusted_quantity);
        END IF;
    END LOOP;

    -- Calculate total current_total_adjusted
    current_total_adjusted := 0;
    FOR valid_order IN SELECT * FROM valid_orders
    LOOP
        current_total_adjusted := current_total_adjusted + valid_order.quantity_adjusted;
    END LOOP;

    -- Evenly distribute the remaining difference across all non-locked orders
    remaining_difference := adjusted_total_quantity - current_total_adjusted;
    SELECT COUNT(*) INTO order_count FROM valid_orders;

    -- The rest to get to the next multiple of unit_total_size
    IF remaining_difference <> 0 THEN
        step := rounding_step_size * SIGN(remaining_difference);
        steps := FLOOR((ABS(remaining_difference) / rounding_step_size) / order_count);

        -- add small step size
        FOR i IN 0..steps - 1 LOOP
            FOR valid_order IN SELECT * FROM valid_orders
            LOOP
                IF NOT valid_order.locked THEN
                    valid_order.quantity_adjusted := valid_order.quantity_adjusted + step;
                END IF;
            END LOOP;
        END LOOP;

        -- calculate total current_total_adjusted again
        current_total_adjusted := 0;
        FOR valid_order IN SELECT * FROM valid_orders
        LOOP
            current_total_adjusted := current_total_adjusted + valid_order.quantity_adjusted;
        END LOOP;

        remaining_difference := adjusted_total_quantity - current_total_adjusted;
        IF remaining_difference <> 0 THEN
            RAISE EXCEPTION 'We have still some remaining difference %', remaining_difference;
        END IF;
    END IF;

    RETURN QUERY SELECT * FROM unnest(valid_orders);
END;
$$;

SELECT kp__adjust_orders(11724);

SELECT DISTINCT(distributions_offer), COUNT(distributions_offer) FROM distributions_orders GROUP BY distributions_offer;