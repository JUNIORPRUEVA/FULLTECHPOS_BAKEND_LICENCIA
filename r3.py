with open("backend/controllers/publicLicenseController.js","r",encoding="utf-8") as f:
    c = f.read()
NL = chr(10)
pb10 = NL.join([
    "          project: {",
    "            monthly_price: Number(project.monthly_price) || 0,",
    "            currency: String(project.currency || 'USD'),",
    "            demo_days: Number(project.demo_days) || 0,",
    "            min_purchase_months: Number(project.min_purchase_months) || 1,",
    "            is_paid_project: Boolean(project.is_paid_project),",
    "            allow_demo: Boolean(project.allow_demo),",
    "            is_active: Boolean(project.is_active)",
    "          }"
])
pb8 = NL.join([
    "        project: {",
    "          monthly_price: Number(project.monthly_price) || 0,",
    "          currency: String(project.currency || 'USD'),",
    "          demo_days: Number(project.demo_days) || 0,",
    "          min_purchase_months: Number(project.min_purchase_months) || 1,",
    "          is_paid_project: Boolean(project.is_paid_project),",
    "          allow_demo: Boolean(project.allow_demo),",
    "          is_active: Boolean(project.is_active)",
    "        }"
])
pb6 = NL.join([
    "      project: {",
    "        monthly_price: Number(project.monthly_price) || 0,",
    "        currency: String(project.currency || 'USD'),",
    "        demo_days: Number(project.demo_days) || 0,",
    "        min_purchase_months: Number(project.min_purchase_months) || 1,",
    "        is_paid_project: Boolean(project.is_paid_project),",
    "        allow_demo: Boolean(project.allow_demo),",
    "        is_active: Boolean(project.is_active)",
    "      }"
])
# 1) ACTIVA
old = "          project_id: project.id" + NL + "        });" + NL + "      }" + NL + "" + NL + "      // Licencia FULL existe pero vencida"
newt = "          project_id: project.id," + NL + "          license_version: Number(fullActivation.license_version) || 1," + NL + "          license_updated_at: fullActivation.updated_at," + NL + pb10 + NL + "        });" + NL + "      }" + NL + "" + NL + "      // Licencia FULL existe pero vencida"
c = c.replace(old, newt, 1)
print("1 OK")
# 2) EXPIRED
old = "          project_id: project.id" + NL + "        });" + NL + "      }" + NL + "    }" + NL + "" + NL + "    // 2) Buscar licencias DEMO activas"
newt = "          project_id: project.id," + NL + "          license_version: Number(fullActivation.license_version) || 1," + NL + "          license_updated_at: fullActivation.updated_at," + NL + pb10 + NL + "        });" + NL + "      }" + NL + "    }" + NL + "" + NL + "    // 2) Buscar licencias DEMO activas"
c = c.replace(old, newt, 1)
print("2 OK")
# 3) DEMO_ACTIVE
old = "          customer_id: demoActivation.customer_id," + NL + "          project_id: project.id" + NL + "        });" + NL + "      }" + NL + "" + NL + "      // Demo vencido"
newt = "          customer_id: demoActivation.customer_id," + NL + "          project_id: project.id," + NL + "          license_version: Number(demoActivation.license_version) || 1," + NL + "          license_updated_at: demoActivation.updated_at," + NL + pb10 + NL + "        });" + NL + "      }" + NL + "" + NL + "      // Demo vencido"
c = c.replace(old, newt, 1)
print("3 OK")
# 4) DEMO_EXPIRED (activation)
old = "        customer_id: demoActivation.customer_id," + NL + "        project_id: project.id" + NL + "      });" + NL + "    }" + NL + "" + NL + "    // 3) Verificar si hubo demo previa"
newt = "        customer_id: demoActivation.customer_id," + NL + "        project_id: project.id," + NL + pb8 + NL + "      });" + NL + "    }" + NL + "" + NL + "    // 3) Verificar si hubo demo previa"
c = c.replace(old, newt, 1)
print("4 OK")
# 5) DEMO_EXPIRED (trial)
old = "        customer_id: trial.customer_id," + NL + "        project_id: project.id" + NL + "      });" + NL + "    }" + NL + "" + NL + "    // 4) No hay licencia ni demo"
newt = "        customer_id: trial.customer_id," + NL + "        project_id: project.id," + NL + pb8 + NL + "      });" + NL + "    }" + NL + "" + NL + "    // 4) No hay licencia ni demo"
c = c.replace(old, newt, 1)
print("5 OK")
# 6) NO_LICENSE
old = "        project_id: project.id" + NL + "    });" + NL + "  } catch (error)"
newt = "        project_id: project.id," + NL + pb6 + NL + "    });" + NL + "  } catch (error)"
c = c.replace(old, newt, 1)
print("6 OK")
with open("backend/controllers/publicLicenseController.js","w",encoding="utf-8") as f:
    f.write(c)
print("ALL DONE")
