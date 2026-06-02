with open("backend/controllers/publicLicenseController.js","r",encoding="utf-8") as f:
    c = f.read()
NL = chr(10)
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
old = "      project_id: project.id" + NL + "    });" + NL + "  } catch (error)"
newt = "      project_id: project.id," + NL + pb6 + NL + "    });" + NL + "  } catch (error)"
print("old count:", c.count(old))
c = c.replace(old, newt, 1)
print("new count:", c.count(old))
with open("backend/controllers/publicLicenseController.js","w",encoding="utf-8") as f:
    f.write(c)
print("ALL DONE")
