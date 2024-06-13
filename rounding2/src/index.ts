export interface Offer {
    id: number;
    unit_count: number;
    unit_size: number;
    step_size: number;
    rounding_step_size: number;
    total_amount?: number;
    total_amount_adjusted?: number;
  }

  export interface Order {
    id: number;
    quantity: number;
    quantity_adjusted?: number;
    quantity_adjusted_locked?: boolean;
    name?: string;
    error?: 'quantity_adjusted_below_zero';
  }

export function adjustOrders(orders: Order[], offer: Offer, debug = false): Order[]  {
    const startTime = new Date();

    if(debug) {
        console.log("Input orders", orders)
        console.log("Input offer", offer)
    }

    // Ensure step_size is not smaller than rounding_step_size
    if (offer.step_size < offer.rounding_step_size) {
        console.warn(
            "Rounding step size is larger than step size, setting rounding step size to step size."
        );
        offer.rounding_step_size = offer.step_size;
    }

    // Filter out orders with quantity 0
    const validOrders = orders.filter(order => order.quantity > 0);

    const unitTotalSize = offer.unit_size * offer.unit_count;
    const totalOrderedQuantity = validOrders.reduce((sum, order) => sum + (order?.quantity_adjusted ?? order.quantity), 0);

    // Total ordered quantity is zero, return orders
    if (totalOrderedQuantity === 0) {
        return orders
    }

    // Determine the target total quantity to adjust to
    const targetTotalQuantity = offer.total_amount_adjusted ?? Math.round(totalOrderedQuantity / unitTotalSize) * unitTotalSize;
    if(debug) {
        console.log("Target Total Adjusted Quantity " + targetTotalQuantity)
    }

    // Calculate scaling factor
    const scaleFactor = targetTotalQuantity / totalOrderedQuantity;
    if(debug) {
        console.log("Scale factor " + scaleFactor)
    }

    // Initial adjustment of order quantities
    let adjustedOrders = validOrders.map(order => {
        if (!order.quantity_adjusted_locked) {
            let adjustedQuantity = order.quantity * scaleFactor;
            adjustedQuantity = Math.round(adjustedQuantity / offer.rounding_step_size) * offer.rounding_step_size;
            adjustedQuantity = Math.max(0, adjustedQuantity);
            return {
                ...order,
                quantity_adjusted: adjustedQuantity
            };
        } else {
            return order
        }
    });

    // Calculate total quantity of adjusted orders
    let currentTotalAdjusted = adjustedOrders.reduce((sum, order) => sum + (order.quantity_adjusted ?? 0), 0);

    // Distribute the remaining difference across all non-locked orders
    let remainingDifference = targetTotalQuantity - currentTotalAdjusted;
    if(debug) {
        console.log("Remaining difference " + remainingDifference)
    }
    const nonLockedOrders = adjustedOrders.filter(order => !order.quantity_adjusted_locked);

    if (remainingDifference !== 0 && nonLockedOrders.length > 0) {
        let step = offer.rounding_step_size * Math.sign(remainingDifference);
        let steps = Math.round(Math.abs(remainingDifference) / offer.rounding_step_size);

        let i = 0
        for (i = 0; i < steps; i++) {
            nonLockedOrders[i % nonLockedOrders.length].quantity_adjusted! += step;
        }
        const nextNonLockedOrder = (nonLockedOrders.length > (i % nonLockedOrders.length) -1) ? 0 : i++

        remainingDifference = targetTotalQuantity - adjustedOrders.reduce((sum, order) => sum + (order.quantity_adjusted ?? 0), 0);
        if(debug) {
            console.log("Still remaining difference " + remainingDifference)
        }
        if (remainingDifference !== 0) {
            nonLockedOrders[nextNonLockedOrder].quantity_adjusted! += remainingDifference;
        }
    }

    // Include locked orders and orders with quantity 0 back into the result with quantity_adjusted set accordingly
    const finalOrders = orders.map(order => {
            if (order.quantity_adjusted_locked) {
                return {
                    ...order,
                    quantity_adjusted: order.quantity_adjusted
                };
            } else if (order.quantity === 0) {
                return {
                    ...order,
                    quantity_adjusted: order.quantity
                };
            } else {
            const adjustedOrder = adjustedOrders.find(adjusted => adjusted.id === order.id);
            if((adjustedOrder?.quantity_adjusted ?? 0) < 0) {
                adjustedOrder!.error = 'quantity_adjusted_below_zero'
                console.warn(`Adjusted order id ${adjustedOrder!.id} is below zero (${adjustedOrder?.quantity_adjusted}).`)
            }
            return adjustedOrder ? adjustedOrder : { ...order, quantity_adjusted: 0 };
        }
    });

    const endTime = new Date();
    const timeDiff = endTime.getTime() - startTime.getTime(); // Time difference in milliseconds

    if(debug) {
        console.log("Output",finalOrders);
        console.log(`Ordered: ${finalOrders.reduce((sum, order) => sum + (order.quantity ?? 0), 0)}`);
        console.log(`Adjusted: ${finalOrders.reduce((sum, order) => sum + (order.quantity_adjusted ?? 0), 0)}`);
        console.log(`Time taken: ${timeDiff}ms`);
    }

    return finalOrders;
}

// Example usage
const offer: Offer = {
    unit_count: 1,
    unit_size: 5,
    step_size: 0.5,
    rounding_step_size: 0.1,
    total_amount_adjusted: 20
};

const orders: Order[] = [
    { id: 1, quantity: 1, name: "Hans", quantity_adjusted_locked: true },
    { id: 2, quantity: 2.4, name: "Rike", quantity_adjusted_locked: false },
    { id: 3, quantity: 3.1, name: "Sebastian", quantity_adjusted_locked: false },
    { id: 4, quantity: 1.5, name: "Bob", quantity_adjusted_locked: true },
    { id: 5, quantity: 1.2, name: "Remy", quantity_adjusted_locked: false },
    { id: 6, quantity: 1.1, name: "Bruno", quantity_adjusted_locked: false },
    { id: 7, quantity: 1.1, name: "Bruno", quantity_adjusted_locked: false },
];