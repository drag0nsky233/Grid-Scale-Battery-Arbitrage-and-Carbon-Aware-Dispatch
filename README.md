# Grid-Scale Battery Dispatch (Case B)

## Overview

This project implements a grid-scale battery dispatch model based on day-ahead electricity prices.
An extension is included to account for carbon intensity using a lambda parameter.

The model is formulated as a linear programming problem and solved in MATLAB.

---

## Model

Decision variables:

* Charging power (P_{ch})
* Discharging power (P_{dis})
* State of charge (E)

Objective:

* Maximise arbitrage profit
* With extension: include carbon penalty on charging

Main constraints:

* Energy balance
* Power limits
* SOC limits
* Final SOC ≥ initial SOC

---

## Data

File used:

* `caseB_grid_battery_market_hourly.csv`

Includes:

* Price (GBP/MWh)
* Carbon intensity (kg/kWh)

Unit conversion:

* Carbon converted to kg/MWh

---

## How to run

Open MATLAB and run:

```matlab
main
```

---

## Outputs

* Total profit
* Emissions (gross and net)
* Energy throughput
* SOC trajectory
* Plots:

  * Profit vs emissions (Pareto front)
  * Emission reduction vs profit loss
  * Time series (price, SOC, dispatch)

---

## Verification

The following checks are included:

* Energy balance consistency
* Power limits respected
* SOC within bounds
* Final SOC constraint satisfied
* Unit conversion check

---

## Extension

Carbon-aware dispatch is implemented by adding a penalty term:

[
\lambda \times carbon(t)
]

A parameter sweep is used to analyse the trade-off between profit and emissions.

---

## Author

Zetao Li
KCL
K25022814
