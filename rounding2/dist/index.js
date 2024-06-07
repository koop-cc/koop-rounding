"use strict";
var UnitMassUnit;
(function (UnitMassUnit) {
    UnitMassUnit["Gram"] = "gram";
    UnitMassUnit["Kilogram"] = "kilogram";
})(UnitMassUnit || (UnitMassUnit = {}));
function adjustOrders(orders, offer) {
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
        return Object.assign(Object.assign({}, order), { quantity_adjusted: adjustedQuantity });
    });
    // Gesamtmenge der angepassten Bestellungen berechnen
    let currentTotalAdjusted = adjustedOrders.reduce((sum, order) => { var _a; return sum + ((_a = order.quantity_adjusted) !== null && _a !== void 0 ? _a : 0); }, 0);
    // Differenz gleichmäßig auf alle Bestellungen aufteilen
    let remainingDifference = adjustedTotalQuantity - currentTotalAdjusted;
    const orderCount = adjustedOrders.length;
    if (remainingDifference !== 0) {
        let step = offer.rounding_step_size * Math.sign(remainingDifference);
        for (let i = 0; i < Math.abs(remainingDifference) / offer.rounding_step_size; i++) {
            adjustedOrders[i % orderCount].quantity_adjusted += step;
        }
        adjustedOrders = adjustedOrders.map(order => {
            var _a;
            let adjustedQuantity = Math.round(((_a = order.quantity_adjusted) !== null && _a !== void 0 ? _a : 0) / offer.rounding_step_size) * offer.rounding_step_size;
            adjustedQuantity = Math.max(0, adjustedQuantity);
            return Object.assign(Object.assign({}, order), { quantity_adjusted: adjustedQuantity });
        });
    }
    return adjustedOrders;
}
// Beispiel-Daten
const offer = {
    offer_id: 97,
    unit_count: 1,
    unit_size: 5,
    unit_massunit: UnitMassUnit.Kilogram,
    step_size: 0.5,
    rounding_step_size: 0.1,
    article_nr: "97"
};
const orders = [
    { order_id: 1, offer_id: 97, quantity: 1, name: 'Hans' },
    { order_id: 2, offer_id: 97, quantity: 2, name: 'Rike' },
    { order_id: 3, offer_id: 97, quantity: 1.5, name: 'Sebastian' }
];
const adjustedOrders = adjustOrders(orders, offer);
console.log(adjustedOrders);
