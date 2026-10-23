---
description: The interview message of an underspecified request. Tests that the questions never ask for the workload name, subscription, resource group or region - parameterized context the stage file supplies.
expected_outcome: a first interview message that asks only customer questions (who reaches the storage account, data access, requirements) and does not ask for the workload short name, subscription id, resource group, region or whether the resource group exists.
tags: [terraform, sandbox, public, interview]
plugins: ["../../.."]
runs: 3
max_turns: 30
timeout_seconds: 600
allowed_tools: [Read, Glob, Grep, Skill, Write, Edit]
---

Ich brauch ein Storage Account in der Sandbox. Terraform mit AVM, standalone, öffentlich
erreichbar, Germany West Central.
