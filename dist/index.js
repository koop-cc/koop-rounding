"use strict";
Object.defineProperty(exports, "__esModule", { value: true });
class koop_rounding {
    bundle;
    orders;
    calculate_distance = (value, bag_size, threshold) => {
        // Calculate the remainder when dividing the value by bag_size
        let remainder = value % bag_size;
        // Calculate the absolute distance to the nearest multiple of bag_size
        let distance = value < bag_size * threshold
            ? bag_size - remainder
            : Math.min(remainder, bag_size - remainder);
        // Normalize the distance by dividing it by bag_size
        let normalizedDistance = distance / bag_size;
        return 1 - normalizedDistance;
    };
    array_not_intersect = (a, b) => {
        return a
            .filter((x) => !b.includes(x))
            .concat(b.filter((x) => !a.includes(x)));
    };
    constructor(bundle, orders) {
        this.bundle = bundle;
        this.orders = orders;
    }
    round = (options) => {
        const min_threshold = options.min_threshold || 0.75;
        const threshold = options.threshold || 0.6;
        const unit_count = this.bundle.unit_count || 1;
        const unit_size = this.bundle.unit_size;
        const step_size = this.bundle.step_size || unit_size;
        const bucket_size = unit_count * unit_size;
        var iterations = 0;
        var error = false;
        var errorMessage = "";
        var totalSumUnscaled = 0;
        var scaled_total_sum = 0;
        var bundles_count = 0;
        var scaled_values = [];
        try {
            // Check if the bucket_size is a multiple of the step_size
            if (unit_size % step_size !== 0) {
                throw new Error("step_size must be a divider of unit_size");
            }
            if (bucket_size === 0) {
                throw new Error("bucket_size must be greater than 0");
            }
            // Adjust the step_size to 1 and the bucket_size acordingly
            const bucket_size_scaled = bucket_size / step_size;
            const scale_factor = bucket_size / bucket_size_scaled;
            // Reduce the user_values by scaling each value by the scale_factor
            // Adding a weight parameter to the user_values object according to the distance to the next bag_size
            const user_values = this.orders.map((user) => {
                if (user.value % step_size !== 0) {
                    throw new Error("a value must be a multiple of step_size");
                }
                return {
                    id: user.id,
                    value_scaled: user.value / scale_factor,
                    value: user.value,
                    locked: user.locked,
                    weight: this.calculate_distance(user.value, unit_size, threshold)
                };
            });
            // Create Weighted Array
            // Calculate the total sum of user values
            let totalSum = user_values.reduce((sum, user) => sum + user.value_scaled, 0);
            totalSumUnscaled = user_values.reduce((sum, user) => sum + user.value, 0);
            // Calculate the amount of buckets needed
            const bundles_count_raw = totalSum / bucket_size_scaled;
            bundles_count = bundles_count_raw < 1
                ? (bundles_count_raw >= min_threshold ? 1 : 0)
                : (bundles_count_raw > Math.floor(bundles_count_raw) + threshold
                    ? Math.ceil(bundles_count_raw)
                    : Math.floor(bundles_count_raw));
            console.log(bundles_count_raw, min_threshold, threshold, bundles_count);
            if (bundles_count === 0) {
                throw new Error("not enough orders to complete at least one bundle.");
            }
            // Calculate the rounded total sum
            let total_sum_original = bundles_count * bucket_size;
            var random_key;
            var pointer;
            do {
                // Scale each value in the user_values object so that the sum of all values is equal to the rounded total sum
                for (let key in user_values) {
                    const user = user_values[key];
                    //console.log(user.value);
                    scaled_values[key] = {
                        rounded_value: user.locked === true && bundles_count > 0
                            ? user.value
                            : user.value_scaled * step_size,
                        value: user.value,
                        weight: user.weight,
                        id: user.id,
                        locked: user.locked
                    };
                }
                // Calculate the scaled total sum
                scaled_total_sum = scaled_values.reduce((sum, scaled_user) => sum + (scaled_user?.rounded_value ?? 0), 0);
                //console.log(`${user_values[0].value_scaled} | ${user_values[1].value_scaled} | ${user_values[2].value_scaled} (${scaled_total_sum} ${total_sum_original})`)
                // Reduce a random value of user_values by 1
                if (scaled_total_sum !== total_sum_original) {
                    let diff = scaled_total_sum > total_sum_original ? -1 : 1;
                    //console.log(scale_factor)
                    const allowed_keys = [];
                    user_values.forEach((v, index) => {
                        if ((diff === 1 || v.value_scaled >= 1) && v.locked !== true) {
                            allowed_keys.push(index);
                        }
                    });
                    if (allowed_keys.length == 0) {
                        throw new Error("Not enough orders to round. Try to unlock locked orders.");
                    }
                    pointer =
                        pointer == null
                            ? Math.floor(Math.random() * allowed_keys.length)
                            : pointer < allowed_keys.length - 2
                                ? ++pointer
                                : 0;
                    random_key = allowed_keys[pointer];
                    user_values[random_key].value_scaled += diff;
                    iterations++;
                }
            } while (scaled_total_sum !== total_sum_original && iterations < 100);
        }
        catch (e) {
            error = true;
            errorMessage = e.message;
        }
        return {
            iterations: iterations,
            total: totalSumUnscaled,
            rounded_total: scaled_total_sum,
            bundles: bundles_count,
            values: error !== false
                ? this.orders
                : scaled_values,
            ...error !== false
                ? { error: errorMessage }
                : {}
        };
    };
}
exports.default = koop_rounding;
