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
    const unitTotalSize = offer.unit_size * offer.unit_count;
    const totalOrderedQuantity = orders.reduce((sum, order) => sum + order.quantity, 0);

    // Zielmenge aufrunden auf das nächste Vielfache der Verkaufseinheit
    const adjustedTotalQuantity = Math.ceil(totalOrderedQuantity / unitTotalSize) * unitTotalSize;

    // Skalierungsfaktor berechnen
    const scaleFactor = adjustedTotalQuantity / totalOrderedQuantity;

    // Initiale Anpassung der Bestellmengen
    let adjustedOrders = orders.map(order => {
        let adjustedQuantity = order.quantity * scaleFactor;
        adjustedQuantity = Math.round(adjustedQuantity / offer.rounding_step_size) * offer.rounding_step_size;
        adjustedQuantity = Math.max(0, adjustedQuantity);
        return {
            ...order,
            quantity_adjusted: adjustedQuantity
        };
    });

    // Gesamtmenge der angepassten Bestellungen berechnen
    let currentTotalAdjusted = adjustedOrders.reduce((sum, order) => sum + (order.quantity_adjusted ?? 0), 0);

    // Differenz gleichmäßig auf alle Bestellungen aufteilen
    let remainingDifference = adjustedTotalQuantity - currentTotalAdjusted;
    const orderCount = adjustedOrders.length;

    if (remainingDifference !== 0) {
        let step = offer.rounding_step_size * Math.sign(remainingDifference);

        for (let i = 0; i < Math.abs(remainingDifference) / offer.rounding_step_size; i++) {
            adjustedOrders[i % orderCount].quantity_adjusted! += step;
        }

        adjustedOrders = adjustedOrders.map(order => {
            let adjustedQuantity = Math.round((order.quantity_adjusted ?? 0) / offer.rounding_step_size) * offer.rounding_step_size;
            adjustedQuantity = Math.max(0, adjustedQuantity);
            return {
                ...order,
                quantity_adjusted: adjustedQuantity
            };
        });
    }

    return adjustedOrders;
}

// Beispiel-Daten
const offer: Offer = {
    offer_id: 97,
    unit_count: 1,
    unit_size: 5,
    unit_massunit: UnitMassUnit.Kilogram,
    step_size: 0.5,
    rounding_step_size: 0.1,
    article_nr: "97"
};

const orders: Order[] = [
    { order_id: 1, offer_id: 97, quantity: 1, name: 'Hans' },
    { order_id: 2, offer_id: 97, quantity: 2, name: 'Rike' },
    { order_id: 3, offer_id: 97, quantity: 1.5, name: 'Sebastian' },
    { order_id: 3, offer_id: 97, quantity: 1.5, name: 'Bob' },
    { order_id: 3, offer_id: 97, quantity: 1.0, name: 'Remy' },
    { order_id: 3, offer_id: 97, quantity: 0.5, name: 'Bruno' }
];

const adjustedOrders = adjustOrders(orders, offer);

console.log(adjustedOrders);
console.log("Bestellt: " + adjustedOrders.reduce((sum, order) => sum + (order.quantity ?? 0), 0));
console.log("Angepasst: " + adjustedOrders.reduce((sum, order) => sum + (order.quantity_adjusted ?? 0), 0));