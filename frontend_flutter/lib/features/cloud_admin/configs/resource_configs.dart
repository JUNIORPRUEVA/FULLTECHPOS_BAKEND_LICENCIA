import 'package:flutter/material.dart';
import '../pages/cloud_resource_page.dart';

/// Configuración para la página de Proyectos
final CloudResourceConfig projectResourceConfig = CloudResourceConfig(
  title: 'Proyectos',
  icon: Icons.folder_copy_outlined,
  endpoint: '/api/admin/projects',
  listKey: 'projects',
  fields: const [
    ResourceField('name', 'Nombre'),
    ResourceField('code', 'Código'),
    ResourceField('monthly_price', 'Precio/mes'),
    ResourceField('currency', 'Moneda'),
    ResourceField('is_active', 'Activo', badge: true),
  ],
  detailFields: const [
    ResourceField('id', 'ID'),
    ResourceField('name', 'Nombre'),
    ResourceField('code', 'Código'),
    ResourceField('description', 'Descripción'),
    ResourceField('monthly_price', 'Precio mensual'),
    ResourceField('currency', 'Moneda'),
    ResourceField('demo_days', 'Días demo'),
    ResourceField('min_purchase_months', 'Meses mínimos'),
    ResourceField('is_paid_project', 'Requiere pago', badge: true),
    ResourceField('allow_demo', 'Permite demo', badge: true),
    ResourceField('is_active', 'Activo', badge: true),
    ResourceField('created_at', 'Creado'),
    ResourceField('updated_at', 'Actualizado'),
  ],
  searchKeys: ['name', 'code'],
);

/// Configuración para la página de Usuarios del sistema
final CloudResourceConfig userResourceConfig = CloudResourceConfig(
  title: 'Usuarios del sistema',
  icon: Icons.admin_panel_settings_outlined,
  endpoint: '/api/admin/platform-users',
  listKey: 'users',
  fields: const [
    ResourceField('username', 'Usuario'),
    ResourceField('email', 'Email'),
    ResourceField('role', 'Rol'),
    ResourceField('is_active', 'Activo', badge: true),
  ],
  detailFields: const [
    ResourceField('id', 'ID'),
    ResourceField('username', 'Usuario'),
    ResourceField('email', 'Email'),
    ResourceField('role', 'Rol'),
    ResourceField('is_active', 'Activo', badge: true),
    ResourceField('created_at', 'Creado'),
  ],
  searchKeys: ['username', 'email'],
);

/// Configuración para la página de Pagos (legacy, usando CloudResourcePage)
final CloudResourceConfig paymentResourceConfig = CloudResourceConfig(
  title: 'Pagos',
  icon: Icons.payments_outlined,
  endpoint: '/api/admin/license-payments',
  listKey: 'orders',
  fields: const [
    ResourceField('customer_name', 'Cliente'),
    ResourceField('project_name', 'Proyecto'),
    ResourceField('total_amount', 'Monto'),
    ResourceField('currency', 'Moneda'),
    ResourceField('status', 'Estado', badge: true),
  ],
  detailFields: const [
    ResourceField('id', 'ID'),
    ResourceField('customer_name', 'Cliente'),
    ResourceField('project_name', 'Proyecto'),
    ResourceField('months', 'Meses'),
    ResourceField('monthly_price', 'Precio mensual'),
    ResourceField('total_amount', 'Total'),
    ResourceField('currency', 'Moneda'),
    ResourceField('status', 'Estado', badge: true),
    ResourceField('provider_order_id', 'PayPal Order ID'),
    ResourceField('provider_capture_id', 'PayPal Capture ID'),
    ResourceField('paid_at', 'Pagado'),
    ResourceField('created_at', 'Creado'),
  ],
  searchKeys: ['customer_name', 'project_name', 'provider_order_id'],
  filterParam: 'status',
  filterOptions: const [
    ResourceFilterOption('Todos', null),
    ResourceFilterOption('Pendientes', 'PENDING'),
    ResourceFilterOption('Pagados', 'PAID'),
    ResourceFilterOption('Fallidos', 'FAILED'),
    ResourceFilterOption('Cancelados', 'CANCELLED'),
  ],
);
