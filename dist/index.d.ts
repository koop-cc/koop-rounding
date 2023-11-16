import type { bundleType, userValue, roundedBundle } from './index.d';
export default class koop_rounding {
    private bundle;
    private orders;
    private calculate_distance;
    private array_not_intersect;
    constructor(bundle: bundleType, orders: userValue[]);
    round: (min_threshold: number, threshold: number) => roundedBundle;
}
