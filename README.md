# koop-rounding
Rounding Algorithm

# Example

Install koop-rounding as a dependency: `npm install http://github.com/koop-cc/koop-rounding` should do the trick.

```
import koop_rounding from "koop-rounding"

const bundle = {
    unit_count: 5,
    unit_size: 1000,
    step_size: 100
}
  
const orders_1 = [
    {id: "Peter", value: 499}, 
    {id: "Paul", value: 3000}, 
    {id: "Mary", value: 1220}, 
    {id: "John", value: 90, locked: true}
]

const r = new koop_rounding(bundle, orders_1);
const rounded = r.round(0.5, 0.5)

console.log(rounded)
```


# Demo App

[Demo App](//koop-cc.github.io/koop-rounding)

There is a vue3 example app in the `example` folder. Read [README](//github.com/koop-cc/koop-rounding/tree/main/example/README.md) in the subfolder for instructions on how to install and compile. Running `npm run build` in the main branch subsequently also runs `npm run build --prefix example` and updates the example. The demo app is automatically deployed on GitHub pages after the build process (see `.github/workflows/deploy.yml`)