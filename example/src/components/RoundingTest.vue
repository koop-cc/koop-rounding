<script setup lang="ts">

import { ref, watch } from 'vue'
import { adjustOrders, type Order, type Offer } from '@library/index'

const offer = ref({
    unit_count: 1,
    unit_size: 5,
    step_size: 0.5,
    rounding_step_size: 0.1,
} as Offer)

var error = ref("")

var members = ref([
    { id: 1, quantity: 1, name: "Hans", locked: true },
    { id: 2, quantity: 2.4, name: "Rike", locked: false },
    { id: 3, quantity: 3.1, name: "Sebastian", locked: false },
    { id: 4, quantity: 1.5, name: "Bob", locked: true },
    { id: 5, quantity: 1.2, name: "Remy", locked: false },
    { id: 6, quantity: 1.1, name: "Bla", locked: false },
    { id: 7, quantity: 1.1, name: "Bruno", locked: false },
] as Order[])

const results = ref([] as Order[])

watch(offer, (val) => {
  doRound()
}, {deep: true})


watch(members, (val) => {
  doRound()
}, {deep: true})

const doRound = () => {
  error.value = ""
  try {
    results.value = adjustOrders(members.value, offer.value)
  } catch(e: any) {
    error.value = e.message as string
  }
}

doRound()

</script>

<template>
  <h1>
    Koop.cc: Rounding Test V2
  </h1>
  <section style="padding: 2rem; border: 1px solid; display: flex; justify-content: space-evenly;">
    <table>
      <thead><tr>
        <td colspan=2>Offer von <i>{{ offer.unit_count }}</i> Einheiten à <i>{{ offer.unit_size }}</i> (kg/g)</td>
      </tr></thead>
      <tr>
        <td>Units in Offer</td>
        <td><input type="number" v-model="offer.unit_count"></td>
      </tr>
      <tr>
        <td>Unit Size</td>
        <td><input type="number" v-model="offer.unit_size"></td>
      </tr>
      <tr>
        <td>Step Size</td>
        <td><input type="number" v-model="offer.step_size"></td>
      </tr>
      <tr>
        <td>Rounding Step Size</td>
        <td><input type="number" v-model="offer.rounding_step_size"></td>
      </tr>

    </table>
    <table>
      <thead><tr>
        <td>Members</td>
        <td>Order</td>
        <td>Locked</td>
      </tr></thead>
      <tr :key="member.id" v-for="member in members">
        <td>
          <input v-model="member.name">
        </td>
        <td>
          <input type="number" v-model="member.quantity">
        </td>
        <td>
          <input type="checkbox" v-model="member.locked">
        </td>
      </tr>
      <tfoot>
        <tr>
          <td><button @click="members.push({id: members.length + 1, quantity: offer.step_size * 1, locked: false, name: ''})">Add Member</button></td>
          <td><button @click="members.pop()">Remove Member</button></td>
        </tr>
      </tfoot>
    </table>
    </section>
  <pre v-if="error != ''" style="clear: both; color: red">{{ error }}</pre>

  <div class="debug" style="clear: both;">
    <h2>Orders:</h2>
    <br>
    <table style="width: 100%; border-collapse: collapse; box-shadow: none;">
      <thead>
        <tr>
          <td>Member</td>
          <td>Ordered</td>
          <td>Adjusted</td>
          <td>Status</td>
        </tr>
      </thead>
      <tr :style="{'background': k%2===0?'#CCC3':''}" :key="m.id" v-for="m,k in results">
        <td>{{ m.name }}</td>
        <td>{{ m.quantity.toFixed(2) }}</td>
        <td>{{ m.quantity_adjusted?.toFixed(2) ?? 0 }}</td>
        <td>{{ (isNaN(m.quantity) || isNaN(m?.quantity_adjusted ?? 0)) ? '⚠️' : m.locked ? '🛑' : '✅' }}</td>
      </tr>
      <tfoot :style="{'background': '#CCCC'}" >
        <td :style="{ fontWeight: 'bold' }">Total</td>
        <td :style="{ fontWeight: 'bold' }">{{ results.reduce((acc, curr) => acc += curr.quantity, 0).toFixed(2) }}</td>
        <td :style="{ fontWeight: 'bold' }">{{ results.reduce((acc, curr) => acc += curr?.quantity_adjusted ?? 0, 0).toFixed(2) }}</td>
        <td></td>
      </tfoot>
    </table>
    <br>
    <br>
    <h2>Legende:</h2>
    <p>
      🛑 Locked<br>
      ⚠️ Error<br>
      ✅ OK
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

.debug {
  font-size: 75;
  border: 1px solid;
}

</style>
