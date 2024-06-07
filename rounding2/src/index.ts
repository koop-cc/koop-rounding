enum UnitMassUnit {
    Gram = 'gram',
    Kilogram = 'kilogram'
}

interface Offer {
    offer_id: number;
    unit_count: number;
    unit_size: number;
    unit_massunit: UnitMassUnit;
    step_size: number;
    rounding_step_size: number;
    article_nr: string;
}

interface Product {
    product_id: number;
    name: string;
    offers: Offer[];
}

interface Order {
    order_id: number;
    offer_id: number;
    quantity: number;
    name: string;
    locked: boolean;
    quantity_adjusted?: number;
}

/**
 * Adjusts the quantities of orders to match the offer's unit size and step size constraints.
 *
 * @param {Order[]} orders - The list of orders to be adjusted.
 * @param {Offer} offer - The offer containing unit size, step size, and rounding step size constraints.
 * @returns {Order[]} - The list of orders with adjusted quantities.
 *
 * The function follows these steps:
 * 1. Ensure `step_size` is not smaller than `rounding_step_size`.
 * 2. Filter out orders with quantity 0.
 * 3. Check for division by zero: If `totalOrderedQuantity` is zero after filtering, return the orders as they are.
 * 4. Round up target quantity to the next multiple of the unit size.
 * 5. Calculate the scaling factor to adjust order quantities.
 * 6. Initial adjustment: Adjust order quantities using the scaling factor and round them to the nearest `rounding_step_size`.
 *    Locked orders retain their original quantity.
 * 7. Distribute remaining difference: Evenly distribute the remaining difference across all non-locked orders in steps of `rounding_step_size`.
 *    After distributing steps, any remaining difference is added to the first non-locked order to ensure the total adjusted quantity matches the target.
 * 8. Include zero quantity and locked orders: Orders with a quantity of 0 are included back in the final result with `quantity_adjusted` set to the original quantity.
 *    Locked orders are included with `quantity_adjusted` set to the original quantity.
 * 9. Performance measurement: Measure the time taken to execute the method and log it.
 */
function adjustOrders(orders: Order[], offer: Offer): Order[] {
    const startTime = new Date();

    // Ensure step_size is not smaller than rounding_step_size
    if (offer.step_size < offer.rounding_step_size) {
        console.log(
            "Rounding step size is larger than step size, setting rounding step size to step size."
        );
        offer.rounding_step_size = offer.step_size;
    }

    // Filter out orders with quantity 0
    const validOrders = orders.filter(order => order.quantity > 0);

    const unitTotalSize = offer.unit_size * offer.unit_count;
    const totalOrderedQuantity = validOrders.reduce((sum, order) => sum + order.quantity, 0);

    if (totalOrderedQuantity === 0) {
        return orders.map(order => ({
            ...order,
            quantity_adjusted: order.quantity
        }));
    }

    // Round up target quantity to the next multiple of the unit size
    const adjustedTotalQuantity = Math.ceil(totalOrderedQuantity / unitTotalSize) * unitTotalSize;

    // Calculate scaling factor
    const scaleFactor = adjustedTotalQuantity / totalOrderedQuantity;

    // Initial adjustment of order quantities
    let adjustedOrders = validOrders.map(order => {
        if (order.locked) {
            return {
                ...order,
                quantity_adjusted: order.quantity
            };
        }
        let adjustedQuantity = order.quantity * scaleFactor;
        adjustedQuantity = Math.round((adjustedQuantity + Number.EPSILON) / offer.rounding_step_size) * offer.rounding_step_size;
        adjustedQuantity = Math.max(0, adjustedQuantity);
        return {
            ...order,
            quantity_adjusted: adjustedQuantity
        };
    });

    // Calculate total quantity of adjusted orders
    let currentTotalAdjusted = adjustedOrders.reduce((sum, order) => sum + (order.quantity_adjusted ?? 0), 0);

    // Evenly distribute the remaining difference across all non-locked orders
    let remainingDifference = adjustedTotalQuantity - currentTotalAdjusted;
    const nonLockedOrders = adjustedOrders.filter(order => !order.locked);

    if (remainingDifference !== 0 && nonLockedOrders.length > 0) {
        let step = offer.rounding_step_size * Math.sign(remainingDifference);
        let steps = Math.round(Math.abs(remainingDifference) / offer.rounding_step_size);

        for (let i = 0; i < steps; i++) {
            nonLockedOrders[i % nonLockedOrders.length].quantity_adjusted! += step;
        }

        remainingDifference = adjustedTotalQuantity - adjustedOrders.reduce((sum, order) => sum + (order.quantity_adjusted ?? 0), 0);

        if (remainingDifference !== 0) {
            nonLockedOrders[0].quantity_adjusted! += remainingDifference;
        }
    }

    // Include locked orders and orders with quantity 0 back into the result with quantity_adjusted set accordingly
    const finalOrders = orders.map(order => {
        if (order.locked || order.quantity === 0) {
            return {
                ...order,
                quantity_adjusted: order.quantity
            };
        } else {
            const adjustedOrder = adjustedOrders.find(adjusted => adjusted.order_id === order.order_id);
            return adjustedOrder ? adjustedOrder : { ...order, quantity_adjusted: 0 };
        }
    });

    const endTime = new Date();
    const timeDiff = endTime.getTime() - startTime.getTime(); // Time difference in milliseconds

    console.log(`Ordered: ${finalOrders.reduce((sum, order) => sum + (order.quantity ?? 0), 0)}`);
    console.log(`Adjusted: ${finalOrders.reduce((sum, order) => sum + (order.quantity_adjusted ?? 0), 0)}`);
    console.log(`Time taken: ${timeDiff}ms`);

    return finalOrders;
}

// Example usage
const offer: Offer = {
    offer_id: 97,
    unit_count: 1,
    unit_size: 5,
    unit_massunit: UnitMassUnit.Kilogram,
    step_size: 0.5,
    rounding_step_size: 0.1, // Changed rounding_step_size to 0.1
    article_nr: "97"
};

const orders: Order[] = [
    { order_id: 1, offer_id: 97, quantity: 1, name: "Hans", locked: true },
    { order_id: 2, offer_id: 97, quantity: 2, name: "Rike", locked: false },
    { order_id: 3, offer_id: 97, quantity: 1.5, name: "Sebastian", locked: false },
    { order_id: 4, offer_id: 97, quantity: 1.5, name: "Bob", locked: true },
    { order_id: 5, offer_id: 97, quantity: 1.0, name: "Remy", locked: false },
    { order_id: 6, offer_id: 97, quantity: 0.5, name: "Bruno", locked: false },
];

const adjustedOrders = adjustOrders(orders, offer);