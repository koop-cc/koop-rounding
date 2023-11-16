import type { bundleType, userValue, roundedBundle, roundingOptions } from './index.d';
export default class koop_rounding {
    private bundle;
    private orders;
    private calculate_distance;
    private array_not_intersect;
    constructor(bundle: bundleType, orders: userValue[]);
    round: (options: roundingOptions) => roundedBundle;
}
