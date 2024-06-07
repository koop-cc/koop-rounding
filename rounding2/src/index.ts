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
    quantity_adjusted?: number;
}

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
        console.log('Total ordered quantity is zero, cannot adjust orders.');
        return orders.map(order => ({
            ...order,
            quantity_adjusted: 0
        }));
    }

    // Round up target quantity to the next multiple of the unit size
    const adjustedTotalQuantity = Math.ceil(totalOrderedQuantity / unitTotalSize) * unitTotalSize;

    // Calculate scaling factor
    const scaleFactor = adjustedTotalQuantity / totalOrderedQuantity;

    // Initial adjustment of order quantities
    let adjustedOrders = validOrders.map(order => {
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

    // Evenly distribute the remaining difference across all orders
    let remainingDifference = adjustedTotalQuantity - currentTotalAdjusted;
    const orderCount = adjustedOrders.length;

    if (remainingDifference !== 0) {
        let steps = Math.floor(Math.abs(remainingDifference) / offer.rounding_step_size);
        let step = offer.rounding_step_size * Math.sign(remainingDifference);

        for (let i = 0; i < steps; i++) {
            adjustedOrders[i % orderCount].quantity_adjusted! += step;
        }

        currentTotalAdjusted = adjustedOrders.reduce((sum, order) => sum + (order.quantity_adjusted ?? 0), 0);
        remainingDifference = adjustedTotalQuantity - currentTotalAdjusted;

        if (remainingDifference !== 0) {
            step = offer.rounding_step_size * Math.sign(remainingDifference);
            adjustedOrders[0].quantity_adjusted! += step;
        }
    }

    // Include orders with quantity 0 back into the result with quantity_adjusted set to 0
    const finalOrders = orders.map(order => {
        const adjustedOrder = adjustedOrders.find(adjusted => adjusted.order_id === order.order_id);
        return adjustedOrder ? adjustedOrder : { ...order, quantity_adjusted: 0 };
    });

    const endTime = new Date();
    const timeDiff = endTime.getTime() - startTime.getTime(); // Time difference in milliseconds

    console.log(finalOrders);
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
    { order_id: 1, offer_id: 97, quantity: 1, name: "Hans" },
    { order_id: 2, offer_id: 97, quantity: 2, name: "Rike" },
    { order_id: 3, offer_id: 97, quantity: 1.5, name: "Sebastian" },
    { order_id: 4, offer_id: 97, quantity: 1.5, name: "Bob" },
    { order_id: 5, offer_id: 97, quantity: 1.0, name: "Remy" },
    { order_id: 6, offer_id: 97, quantity: 0.5, name: "Bruno" },
];

const adjustedOrders = adjustOrders(orders, offer);

