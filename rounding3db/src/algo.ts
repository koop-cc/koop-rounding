class AlgoError {
  constructor(message: string) {
    this.message = message;
  }

  public readonly message: string;
}

const createAlgoError = (message: string) => {
  return new AlgoError(message);
};

interface RoundingOffer {
  id: number;
  unit_count: number;
  unit_size: number;
  step_size: number;
  rounding_step_size: number;
  total_amount?: number;
}

interface RoundingOrder {
  id: number;
  name?: string;
  quantity: number;
  quantity_adjusted?: number;
  quantity_adjusted_locked: boolean;
}

/**
 * Executes the algorithm
 * @param input as a string JSON
 * @returns a string with the result as string JSON
 */
function executeAlgo(input: string) {
  const parsedInput = JSON.parse(input);
  const { orders, offer } = validateInput(parsedInput);
  const adjustedOrders = adjustOrders(orders, offer);
  const result = {
    offer,
    orders: {
      origin: orders,
      adjusted: adjustedOrders,
    },
  };
  return JSON.stringify(result);
}

/**
 * Validates the input if all fields are set in the objects which are necessary
 * @param input
 * @returns the validated objects otherwise it throws
 */
function validateInput(input: any): {
  orders: RoundingOrder[];
  offer: RoundingOffer;
} {
  if (typeof input !== "object" || input === null) {
    throw createAlgoError("Input must be an object");
  }

  const { orders, offer } = input;

  if (!Array.isArray(orders)) {
    throw createAlgoError("Orders must be an array");
  }

  orders.forEach((order) => {
    if (typeof order.id !== "number") {
      throw createAlgoError("Each order must have an id of type number");
    }
    if (typeof order.quantity !== "number") {
      throw createAlgoError("Each order must have a quantity of type number");
    }
    if (
      order.quantity_adjusted_locked !== undefined &&
      typeof order.quantity_adjusted_locked !== "boolean"
    ) {
      throw createAlgoError(
        "quantity_adjusted_locked must be a boolean if defined"
      );
    }
    if (
      order.quantity_adjusted !== undefined &&
      typeof order.quantity_adjusted !== "number"
    ) {
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
    throw createAlgoError(
      "Offer must have a rounding_step_size of type number"
    );
  }
  if (typeof offer.unit_count !== "number") {
    throw createAlgoError("Offer must have a unit_count of type number");
  }

  return { orders, offer };
}

/**
 * Adjusts the quantities of orders to match the offer's unit size and step size constraints.
 *
 * @param {OptimizeOrder[]} orders - The list of orders to be adjusted.
 * @param {OptimizeOffer} offer - The offer containing unit size, step size, and rounding step size constraints.
 * @returns {OptimizeOrder[]} - The list of orders with adjusted quantities.
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
function adjustOrders(
  orders: RoundingOrder[],
  offer: RoundingOffer
): RoundingOrder[] {
  const startTime = new Date();

  // Check if every order has an id
  const hasId = orders.every(
    (order) =>
      order.id !== undefined &&
      order.id !== null &&
      orders.filter((o) => o.id === order.id).length === 1
  );
  if (!hasId) {
    throw createAlgoError(
      "Algo error: all orders must have an id and it must be unique"
    );
  }

  // Ensure step_size is not smaller than rounding_step_size
  if (offer.step_size < offer.rounding_step_size) {
    // eslint-disable-next-line no-console
    console.warn(
      "Rounding step size is larger than step size, setting rounding step size to step size."
    );
    offer.rounding_step_size = offer.step_size;
  }

  // Filter out orders with quantity 0
  const validOrders = orders.filter((order) => order.quantity > 0);

  const unitTotalSize = offer.unit_size * offer.unit_count;
  const totalOrderedQuantity = validOrders.reduce(
    (sum, order) => sum + order.quantity,
    0
  );

  if (totalOrderedQuantity === 0) {
    return orders.map((order) => ({
      ...order,
      quantity_adjusted: order.quantity,
    }));
  }

  // Round up target quantity to the next multiple of the unit size
  const adjustedTotalQuantity =
    Math.ceil(totalOrderedQuantity / unitTotalSize) * unitTotalSize;

  // Calculate scaling factor
  const scaleFactor = adjustedTotalQuantity / totalOrderedQuantity;

  // Initial adjustment of order quantities
  const adjustedOrders = validOrders.map((order) => {
    if (order.quantity_adjusted_locked) {
      return {
        ...order,
        quantity_adjusted: order.quantity,
      };
    }
    let adjustedQuantity = order.quantity * scaleFactor;
    adjustedQuantity =
      Math.round(
        (adjustedQuantity + Number.EPSILON) / offer.rounding_step_size
      ) * offer.rounding_step_size;
    adjustedQuantity = Math.max(0, adjustedQuantity);
    return {
      ...order,
      quantity_adjusted: adjustedQuantity,
    };
  });

  // Calculate total quantity of adjusted orders
  const currentTotalAdjusted = adjustedOrders.reduce(
    (sum, order) => sum + (order.quantity_adjusted ?? 0),
    0
  );

  // Evenly distribute the remaining difference across all non-locked orders
  let remainingDifference = adjustedTotalQuantity - currentTotalAdjusted;
  const nonLockedOrders = adjustedOrders.filter(
    (order) => !order.quantity_adjusted_locked
  );

  if (remainingDifference !== 0 && nonLockedOrders.length > 0) {
    const step = offer.rounding_step_size * Math.sign(remainingDifference);
    const steps = Math.round(
      Math.abs(remainingDifference) / offer.rounding_step_size
    );

    for (let i = 0; i < steps; i++) {
      nonLockedOrders[i % nonLockedOrders.length].quantity_adjusted! += step;
    }

    remainingDifference =
      adjustedTotalQuantity -
      adjustedOrders.reduce(
        (sum, order) => sum + (order.quantity_adjusted ?? 0),
        0
      );

    if (remainingDifference !== 0) {
      nonLockedOrders[0].quantity_adjusted! += remainingDifference;
    }
  }

  // Include locked orders and orders with quantity 0 back into the result with quantity_adjusted set accordingly
  const finalOrders = orders.map((order) => {
    if (order.quantity_adjusted_locked || order.quantity === 0) {
      return {
        ...order,
        quantity_adjusted: order.quantity,
      };
    } else {
      const adjustedOrder = adjustedOrders.find(
        (adjusted) => adjusted.id === order.id
      );
      return adjustedOrder || { ...order, quantity_adjusted: 0 };
    }
  });

  const endTime = new Date();
  const timeDiff = endTime.getTime() - startTime.getTime(); // Time difference in milliseconds

  // eslint-disable-next-line no-console
  console.log("Algo final orders", finalOrders);
  // eslint-disable-next-line no-console
  console.log(
    `Algo ordered sum: ${finalOrders.reduce(
      (sum, order) => sum + (order.quantity ?? 0),
      0
    )}`
  );
  // eslint-disable-next-line no-console
  console.log(
    `Algo adjusted sum: ${finalOrders.reduce(
      (sum, order) => sum + (order.quantity_adjusted ?? 0),
      0
    )}`
  );
  // eslint-disable-next-line no-console
  console.log(`Time taken: ${timeDiff}ms`);

  return finalOrders;
}