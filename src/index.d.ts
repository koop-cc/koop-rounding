/**
 * offerType: defines a offer
 */
export interface offerType {
  /**
   * number of units within a offer.
   */
  unit_count: number;

  /**
   * size of a unit within a offer.
   */
  unit_size: number;

  /**
   * step size to increase or decrease a ordered amount.
   * must be a divider of unit_size. defaults to unit_size
   * if omitted.
   */
  step_size: number;

  /**
   * step size to round the results.
   * must be a divider of step_size and smaller or
   * equal to step_size. defaults to unit_size
   * if omitted.
   */
  rounding_step_size?: number;
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
   * Weight: threshold > weight < 1. The closer a value is to a offer,
   * the closer it is to 1.
   */
  weight?: number;
}

/**
 * roundedOffer: processed offer consisting of rounded user values
 * and rounded totals.
 */
export interface roundedOffer {
  /**
   * Grand total of order
   */
  total: number;

  /**
   * Rounded grand total of order
   */
  rounded_total: number;

  /**
   * Number of offers required for this order
   */
  offers: number;

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

/**
 * Options for Rounding Algorithm
 */
export interface roundingOptions {
  /**
   * Threshold for rounding up to next offer count.
   * 0.5 means: upper 50% -> plus one offer,
   * lower 50% -> minus one offer.
   * Default: 0.6
   */
  threshold?: number,

  /**
   * Threshold for rounding up the first offer.
   * 1.0 means the total products must at least
   * the size of one offer.
   * Default: 0.75
   */
  min_threshold?: number
}