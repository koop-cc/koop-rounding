<script setup lang="ts">

import { ref, watch } from 'vue'
import type { offerType, userValue, roundedOffer } from '@library/index.d'
import koop_rounding from '@library/index'

const threshold = ref(0.6 as number)

const min_threshold = ref(0.75 as number)

const offer = ref({
  unit_count: 1,
  unit_size: 1000,
  step_size: 100,
  rounding_step_size: 10
} as offerType)

var error = ref(null as any)

var members = ref([
  {
    id: "Hans",
    value: 400
  },
  {
    id: "Petra",
    value: 400
  },
  {
    id: "Franz",
    value: 100
  }
] as userValue[])

var rounded = ref({} as roundedOffer)

watch(offer, (val) => {
  doRound()
}, {deep: true})

watch(min_threshold, (val) => {
  doRound()
}, {deep: true})


watch(threshold, (val) => {
  doRound()
}, {deep: true})


watch(members, (val) => {
  doRound()
}, {deep: true})

const doRound = () => {
  error = null
  const r = new koop_rounding(offer.value, members.value)
  try {
    rounded.value = r.round({
      min_threshold: min_threshold.value * 1,
      threshold: threshold.value * 1
    })
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
  <header style="margin-bottom: 2rem;">
    <ol>
      <li>Anzahl Offers der Bestellung wird ermittelt</li>
      <li>Offers &lt; 1 ? Wenn &gt; min_threshold, aufrunden auf 1</li>
      <li>Offers &gt; 1 ? Wenn &gt; threshold, aufrunden auf nächst höheres Offer, sonst abrunden</li>
      <li>Werte Testen: Alle Products müssen teilbar sein durch step_size</li>
      <li>Loop Starten:
        <ol>
          <li>Alle Bestellungen zusammenzählen</li>
          <li>im ersten Durchgang:
            <ol>
              <li>Wenn Total > Anzahl Offers * offer_size, dann zufälligen (unlocked) Wert nehmen und um 1 Schritt reduzieren</li>
              <li>Wenn Total &lt; Anzahl Offers * offer_size, dann zufälligen (unlocked) Wert nehmen und um 1 Schritt erhöhen</li>
            </ol>
          </li>
          <li>in den folgenden Durchgängen:
            <ol>
              <li>Wenn Total > Anzahl Offers * offer_size, dann nächsten (oder ersten) (unlocked) Wert nehmen und um 1 Schritt reduzieren</li>
              <li>Wenn Total &lt; Anzahl Offers * offer_size, dann nächsten (oder ersten) (unlocked) Wert nehmen und um 1 Schritt erhöhen</li>
            </ol>
          </li>
          <li>
            Test:
            <ol>
              <li>Repeat: Wenn Total &lt;&gt; Anzahl Offers * offer_size, wiederholen.</li>
              <li>OK: Wenn Total == Anzahl Offers * offer_size, abschliessen.</li>
              <li>Error: Falls keine Werte vorhanden sind, die gerundet werden können, oder falls ein Wert auf -1 fällt, abbrechen.</li>
            </ol>
          </li>
        </ol>
      </li>
    </ol>
  </header>
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
      <tr>
        <td>Threshold*</td>
        <td><input v-model="threshold"></td>
      </tr>
      <tr>
        <td>Threshold min.*</td>
        <td><input v-model="min_threshold"></td>
      </tr>
      <tr style="font-size: 75%">
        <td>threshold</td>
        <td>
          Grenzwert zum Aufrunden<br>
          auf das nächste Offer
        </td>
      </tr>
      <tr style="font-size: 75%">
        <td>min_Threshold</td>
        <td>
          Grenzwert zum aufrunden<br>
          auf das erste Offer<br>
          (default 0.5 * offer size)
        </td>
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
          <td><button @click="members.push({id: `Member ${members.length + 1}`, value: offer.step_size * 1})">Add Member</button></td>
          <td><button @click="members.pop()">Remove Member</button></td>
        </tr>
      </tfoot>
    </table>
    </section>
  <pre v-if="rounded.error" style="clear: both; color: red">{{ rounded.error }}</pre>

  <div class="debug" style="clear: both;">
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
        <td>{{ m.locked ? '🛑' : Math.abs(m.value - (m.rounded_value ?? 0)) >= (2 * offer.step_size) ? '⚠️' : '✅' }}</td>
      </tr>
    </table>
    <br>
    <h2>Stats:</h2>
    <p>Iterations: {{ rounded.iterations }}</p>
    <p>Total: {{ rounded.total }}</p>
    <p>Rounded: {{ rounded.rounded_total }}</p>
    <p>Offers: {{ rounded.offers }}</p>
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

.debug {
  font-size: 75;
  border: 1px solid;
}

</style>
