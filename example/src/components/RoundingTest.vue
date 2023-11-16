<script setup lang="ts">

import { ref, watch } from 'vue'
import type { bundleType, userValue, roundedBundle } from '@library/index.d'
import koop_rounding from '@library/index'


const bundle = ref({
  unit_count: 1,
  unit_size: 1000,
  step_size: 100
} as bundleType)

var error = ref(null as any)

var members = ref([{
  id: "Member 1",
  value: 500
}] as userValue[])

var rounded = ref({} as roundedBundle)

watch(bundle, (val) => {
  doRound()
}, {deep: true})

watch(members, (val) => {
  doRound()
}, {deep: true})

const doRound = () => {
  error = null
  const r = new koop_rounding(bundle.value, members.value)
  try {
    rounded.value = r.round(0.5)
  } catch (e:any) {
    error = e
  }
}

doRound()

</script>

<template>
  <h1>
    Koop.cc: Rounding Test
  </h1>
  <table style="float: left">
    <thead><tr>
      <td colspan=2>Bundle</td>
    </tr></thead>
    <tr>
      <td>Units in Bundle</td>
      <td><input type="number" v-model="bundle.unit_count"></td>
    </tr>
    <tr>
      <td>Unit Size</td>
      <td><input type="number" v-model="bundle.unit_size"></td>
    </tr>
    <tr>
      <td>Step Size</td>
      <td><input type="number" v-model="bundle.step_size"></td>
    </tr> 
    <tr>
      <td colspan="2">Verkaufseinheit von {{ bundle.unit_count }} Einheiten à {{ bundle.unit_size }} (kg/g)</td>
    </tr> 
  </table>
  <table style="float: right">
    <thead><tr>
      <td>Members</td>
      <td>Order</td>
      <td>Locked</td>
    </tr></thead>
    <tr :key="member.id" v-for="member in members">
      <td>
        <input v-model="member.id">
      </td>
      <td>
        <input type="number" v-model="member.value">
      </td>
      <td>
        <input type="checkbox" v-model="member.locked">
      </td>      
    </tr>
    <tfoot>
      <tr>
        <td><button @click="members.push({id: `Member ${members.length + 1}`, value: bundle.step_size * 1})">Add Member</button></td>
        <td><button @click="members.pop()">Remove Member</button></td>
      </tr>
    </tfoot>
  </table>  

  

  <pre style="clear: both; color: red" v-if="error">{{ error }}</pre>

  <div style="clear: both;" v-else>
    <h2>Orders:</h2>
    <br>
    <table style="width: 100%; border-collapse: collapse; box-shadow: none;">
      <thead>
        <tr>
          <td>Member</td>
          <td>Ordered</td>
          <td>Rounded</td>
          <td>Status</td>
        </tr>
      </thead>
      <tr :style="{'background': k%2===0?'#CCC3':''}" :key="m.id" v-for="m,k in rounded.values">
        <td>{{ m.id }}</td>
        <td>{{ m.value }}</td>        
        <td>{{ m.rounded_value }}</td>
        <td>{{ m.locked ? '🛑' : Math.abs(m.value - (m.rounded_value ?? 0)) >= (2 * bundle.step_size) ? '⚠️' : '✅' }}</td>        
      </tr>
    </table>
    <br>
    <h2>Stats:</h2>
    <p>Iterations: {{ rounded.iterations }}</p>
    <p>Total: {{ rounded.total }}</p>    
    <p>Rounded: {{ rounded.rounded_total }}</p>
    <p>Bundles: {{ rounded.bundles }}</p>
    <br>
    <h2>Legende:</h2>
    <p>
      🛑 Locked<br>
      ⚠️ Delta &gt; or equal 2 * step_size<br>
      ✅ Delta &lt; * step_size
    </p>
  </div>

  <!--
    <pre style="clear: both" v-else>{{ rounded }}</pre>
  -->


</template>

<style scoped>
h1 {
  font-weight: 500;
  font-size: 2.6rem;
  position: relative;
  top: -10px;
}

h3 {
  font-size: 1.2rem;
}

table {
  box-shadow: 1px 1px 10px 2px #00000022;
  padding: 1rem;
}

thead td {
  padding-bottom: 1rem;
  font-weight: bold;  
}

input[type="number"] {
  appearance: none;
  border: none;
  padding: 0.5rem;
  font: inherit;
  background: transparent;
  border-bottom: 1px solid;
}

</style>
