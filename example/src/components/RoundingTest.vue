<script setup lang="ts">

import { ref, watch, computed, unref } from 'vue'
import { adjustOrders, type Order, type Offer } from '@library/index'

const offer = ref({
    unit_count: 1,
    unit_size: 5,
    step_size: 0.5,
    rounding_step_size: 0.1,
    total_amount: undefined,
    total_amount_adjusted: undefined
} as Offer)

var error = ref("")

var members = ref([
    { id: 1, name: "Hans",quantity: 1, },
    { id: 2, name: "Rike", quantity: 2.4, quantity_adjusted: 3, },
    { id: 3, name: "Sebi", quantity: 3.1,  },
    { id: 4, name: "Bob", quantity: 1.5, quantity_adjusted: 4, },
    { id: 5, name: "Remy", quantity: 1.2, },
    { id: 6, name: "Björn", quantity: 1.1,  },
    { id: 7, name: "Bruno", quantity: 1.1, },
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
    const inputOrders = members.value.map((item) => ({
      ...item,
      quantity_adjusted: Number(item.quantity_adjusted) == 0 ? undefined : item.quantity_adjusted,
      quantity_adjusted_locked: Number(item.quantity_adjusted) > 0
    }))
    const inputOffer = {
      ...offer.value,
      total_amount_adjusted : Number(offer.value.total_amount_adjusted) == 0 ? undefined : offer.value.total_amount_adjusted,
    }
    const debug = false
    results.value = adjustOrders(inputOrders, inputOffer, debug)
  } catch(e: any) {
    error.value = e.message as string
  }
}

doRound()

const total_amount = computed(() => (members.value.reduce((acc, curr) => acc + curr.quantity, 0)).toFixed(2))

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
        <td><input type="number" v-model="offer.unit_count" :min="0" step="1"></td>
      </tr>
      <tr>
        <td>Unit Size</td>
        <td><input type="number" v-model="offer.unit_size" :min="0" step="0.1"></td>
      </tr>
      <tr>
        <td>Step Size</td>
        <td><input type="number" v-model="offer.step_size" :min="0" step="0.1"></td>
      </tr>
      <tr>
        <td>Rounding Step Size</td>
        <td><input type="number" v-model="offer.rounding_step_size" :min="0" step="0.1"></td>
      </tr>
    </table>

    <table>
    <thead>
      <tr>
        <td></td>
        <td>Total (unchangeable)</td>
        <td>Total Adjusted</td>
        <td>Locked</td>
      </tr>
    </thead>
      <tr>
        <td>

        </td>
        <td>
          <input type="number" v-model="total_amount" readonly>
        </td>
        <td>
          <input type="number" v-model="offer.total_amount_adjusted" :min="0" :step="offer.unit_size * offer.unit_count">
        </td>
        <td>
          <input type="checkbox"
          :checked="offer.total_amount_adjusted !== undefined && offer.total_amount_adjusted > 0"
          @change="offer.total_amount_adjusted = (offer.total_amount_adjusted! > 0) ? undefined : offer.total_amount_adjusted"
          :disabled="offer.total_amount_adjusted === undefined || !(offer.total_amount_adjusted > 0)"
          >
          </td>
        </tr>
      <thead :style="{marginTop: 20}"><tr>
        <td>Members</td>
        <td>Quantity (user)</td>
        <td>Quantity (adjusted)</td>
        <td>Locked</td>
      </tr></thead>
      <tr :key="member.id" v-for="member,index in members">
        <td>
          <input v-model="member.name">
        </td>
        <td>
          <input type="number" v-model="member.quantity" :min="0" :step="offer.step_size">
        </td>
        <td>
          <input type="number" v-model="member.quantity_adjusted" :min="0" :step="offer.rounding_step_size">
        </td>
        <td>
          <input type="checkbox"
          :checked="member.quantity_adjusted !== undefined && member.quantity_adjusted > 0"
          @change="member.quantity_adjusted = (member.quantity_adjusted! > 0) ? undefined : member.quantity_adjusted"
          :disabled="member.quantity_adjusted === undefined || !(member.quantity_adjusted > 0)"
          >
        </td>
      </tr>
      <tfoot>
        <tr>
          <td><button @click="members.push({id: members.length + 1, quantity: offer.step_size * 1, quantity_adjusted_locked: false, name: ''})">Add Member</button></td>
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
        <td>{{ Number(m.quantity_adjusted).toFixed(2) }}</td>
        <td>{{ (isNaN(m.quantity) || isNaN(Number(m?.quantity_adjusted)) || m?.error !== undefined ) ? '⚠️' : m.quantity_adjusted_locked ? '🛑' : '✅' }}</td>
      </tr>
      <tfoot :style="{'background': '#CCCC'}" >
        <td :style="{ fontWeight: 'bold' }">Total</td>
        <td :style="{ fontWeight: 'bold' }">{{ results.reduce((acc, curr) => acc += curr?.quantity ?? 0, 0).toFixed(2) }}</td>
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
