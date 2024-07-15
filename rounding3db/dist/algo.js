"use strict";
var __assign = (this && this.__assign) || function () {
    __assign = Object.assign || function(t) {
        for (var s, i = 1, n = arguments.length; i < n; i++) {
            s = arguments[i];
            for (var p in s) if (Object.prototype.hasOwnProperty.call(s, p))
                t[p] = s[p];
        }
        return t;
    };
    return __assign.apply(this, arguments);
};
var AlgoError = (function () {
    function AlgoError(message) {
        this.message = message;
    }
    return AlgoError;
}());
var createAlgoError = function (message) {
    return new AlgoError(message);f
};
function executeAlgo(input) {
    var parsedInput = JSON.parse(input);
    var _a = validateInput(parsedInput), orders = _a.orders, offer = _a.offer;
    var adjustedOrders = adjustOrders(orders, offer);
    var result = {
        offer: offer,
        orders: {
            origin: orders,
            adjusted: adjustedOrders,
        },
    };
    return JSON.stringify(result);
}
function validateInput(input) {
    if (typeof input !== "object" || input === null) {
        throw createAlgoError("Input must be an object");
    }
    var orders = input.orders, offer = input.offer;
    if (!Array.isArray(orders)) {
        throw createAlgoError("Orders must be an array");
    }
    orders.forEach(function (order) {
        if (typeof order.id !== "number") {
            throw createAlgoError("Each order must have an id of type number");
        }
        if (typeof order.quantity !== "number") {
            throw createAlgoError("Each order must have a quantity of type number");
        }
        if (order.quantity_adjusted_locked !== undefined &&
            typeof order.quantity_adjusted_locked !== "boolean") {
            throw createAlgoError("quantity_adjusted_locked must be a boolean if defined");
        }
        if (order.quantity_adjusted !== undefined &&
            typeof order.quantity_adjusted !== "number") {
            throw createAlgoError("quantity_adjusted must be a number if defined");
        }
    });
    if (typeof offer !== "object" || offer === null) {
        throw createAlgoError("Offer must be an object");
    }
    if (typeof offer.unit_size !== "number") {
        throw createAlgoError("Offer must have a unit_size of type number");
    }
    if (typeof offer.step_size !== "number") {
        throw createAlgoError("Offer must have a step_size of type number");
    }
    if (typeof offer.rounding_step_size !== "number") {
        throw createAlgoError("Offer must have a rounding_step_size of type number");
    }
    if (typeof offer.unit_count !== "number") {
        throw createAlgoError("Offer must have a unit_count of type number");
    }
    return { orders: orders, offer: offer };
}
function adjustOrders(orders, offer) {
    var startTime = new Date();
    var hasId = orders.every(function (order) {
        return order.id !== undefined &&
            order.id !== null &&
            orders.filter(function (o) { return o.id === order.id; }).length === 1;
    });
    if (!hasId) {
        throw createAlgoError("Algo error: all orders must have an id and it must be unique");
    }
    if (offer.step_size < offer.rounding_step_size) {
        console.warn("Rounding step size is larger than step size, setting rounding step size to step size.");
        offer.rounding_step_size = offer.step_size;
    }
    var validOrders = orders.filter(function (order) { return order.quantity > 0; });
    var unitTotalSize = offer.unit_size * offer.unit_count;
    var totalOrderedQuantity = validOrders.reduce(function (sum, order) { return sum + order.quantity; }, 0);
    if (totalOrderedQuantity === 0) {
        return orders.map(function (order) { return (__assign(__assign({}, order), { quantity_adjusted: order.quantity })); });
    }
    var adjustedTotalQuantity = Math.ceil(totalOrderedQuantity / unitTotalSize) * unitTotalSize;
    var scaleFactor = adjustedTotalQuantity / totalOrderedQuantity;
    var adjustedOrders = validOrders.map(function (order) {
        if (order.quantity_adjusted_locked) {
            return __assign(__assign({}, order), { quantity_adjusted: order.quantity });
        }
        var adjustedQuantity = order.quantity * scaleFactor;
        adjustedQuantity =
            Math.round((adjustedQuantity + Number.EPSILON) / offer.rounding_step_size) * offer.rounding_step_size;
        adjustedQuantity = Math.max(0, adjustedQuantity);
        return __assign(__assign({}, order), { quantity_adjusted: adjustedQuantity });
    });
    var currentTotalAdjusted = adjustedOrders.reduce(function (sum, order) { var _a; return sum + ((_a = order.quantity_adjusted) !== null && _a !== void 0 ? _a : 0); }, 0);
    var remainingDifference = adjustedTotalQuantity - currentTotalAdjusted;
    var nonLockedOrders = adjustedOrders.filter(function (order) { return !order.quantity_adjusted_locked; });
    if (remainingDifference !== 0 && nonLockedOrders.length > 0) {
        var step = offer.rounding_step_size * Math.sign(remainingDifference);
        var steps = Math.round(Math.abs(remainingDifference) / offer.rounding_step_size);
        for (var i = 0; i < steps; i++) {
            nonLockedOrders[i % nonLockedOrders.length].quantity_adjusted += step;
        }
        remainingDifference =
            adjustedTotalQuantity -
                adjustedOrders.reduce(function (sum, order) { var _a; return sum + ((_a = order.quantity_adjusted) !== null && _a !== void 0 ? _a : 0); }, 0);
        if (remainingDifference !== 0) {
            nonLockedOrders[0].quantity_adjusted += remainingDifference;
        }
    }
    var finalOrders = orders.map(function (order) {
        if (order.quantity_adjusted_locked || order.quantity === 0) {
            return __assign(__assign({}, order), { quantity_adjusted: order.quantity });
        }
        else {
            var adjustedOrder = adjustedOrders.find(function (adjusted) { return adjusted.id === order.id; });
            return adjustedOrder || __assign(__assign({}, order), { quantity_adjusted: 0 });
        }
    });
    var endTime = new Date();
    var timeDiff = endTime.getTime() - startTime.getTime();
    console.log("Algo final orders", finalOrders);
    console.log("Algo ordered sum: ".concat(finalOrders.reduce(function (sum, order) { var _a; return sum + ((_a = order.quantity) !== null && _a !== void 0 ? _a : 0); }, 0)));
    console.log("Algo adjusted sum: ".concat(finalOrders.reduce(function (sum, order) { var _a; return sum + ((_a = order.quantity_adjusted) !== null && _a !== void 0 ? _a : 0); }, 0)));
    console.log("Time taken: ".concat(timeDiff, "ms"));
    return finalOrders;
}
