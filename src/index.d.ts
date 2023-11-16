/**
 * bundleType: defines a bundle
 */
export interface bundleType {
  /**
   * number of units within a bundle.
   */
  unit_count: number;

  /**
   * size of a unit within a bundle.
   */
  unit_size: number;

  /**
   * step size to increase or decrease a ordered amount.
   * must be a divider of unit_size
   */
  step_size: number;
}

/**
 * userValue: defining a single order
 */
export interface userValue {
  /**
   * User Id
   */
  id: any;

  /**
   * Ordered Amount
   */

  value: number;

  /**
   * Locked values cannot change
   */
  locked?: boolean;

  /**
   * Rounded amount
   */
  rounded_value?: number;

  /**
   * Weight: threshold > weight < 1. The closer a value is to a bundle,
   * the closer it is to 1.
   */
  weight?: number;
}

/**
 * roundedBundle: processed bundle consisting of rounded user values
 * and rounded totals.
 */
export interface roundedBundle {
  /**
   * Grand total of order
   */
  total: number;

  /**
   * Rounded grand total of order
   */
  rounded_total: number;

  /**
   * Number of bundles required for this order
   */
  bundles: number;

  /**
   * Processed user values of this order
   */
  values: userValue[];

  /**
   * Iteration: How many times the algorithm needed to loop
   * to find a correct result
   */
  iterations: number;

  /**
   * Error: false or string 
   */
  error?: string;
}
