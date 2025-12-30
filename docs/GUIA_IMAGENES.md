# 📸 Guía de Cómo Agregar Imágenes a FULLTECH POS Web

## 📂 Estructura de Carpetas

```
fulltech_pos_web/
│
├── index.html
├── assets/
│   ├── css/
│   │   └── styles.css
│   ├── img/                    ← AQUÍ VAN LAS IMÁGENES
│   │   ├── logo_fulltech.png
│   │   ├── hero-image.png      ← Imagen del hero
│   │   ├── feature-1.png       ← Características (opcional)
│   │   ├── feature-2.png
│   │   └── system-screenshot.png
│   └── js/
│       └── script.js
└── downloads/
    └── fulltech-pos-demo.exe
```

---

## 🎯 Dónde Agregar Imágenes

### **1️⃣ Logo (Ya existe)**
- **Ubicación:** `assets/img/logo_fulltech.png`
- **Tamaño recomendado:** 200x200px
- **Uso:** Se muestra en el header del hero
- **Archivo HTML:** Línea 16

```html
<img src="assets/img/logo_fulltech.png" alt="FULLTECH POS Logo" class="logo">
```

---

### **2️⃣ Imagen del Placeholder (Hero Section)**
- **Ubicación:** Reemplazar el placeholder en línea 27
- **Tamaño recomendado:** 500x500px o 1200x900px
- **Formato:** PNG, JPG, WEBP
- **Descripción:** Captura de pantalla del sistema o mockup del dashboard

**Cambiar esto:**
```html
<div class="placeholder-image">
    <p>Imagen del Sistema</p>
</div>
```

**Por esto:**
```html
<img src="assets/img/hero-dashboard.png" alt="FULLTECH POS Dashboard" class="hero-system-image">
```

**Agregar CSS (en styles.css):**
```css
.hero-system-image {
    width: 100%;
    max-width: 400px;
    border-radius: 15px;
    box-shadow: 0 15px 40px rgba(0, 0, 0, 0.2);
    animation: slideInUp 0.8s ease-out 0.2s backwards;
}
```

---

### **3️⃣ Imágenes en Tarjetas de Características (Opcional)**
- **Tamaño:** 80x80px o 120x120px
- **Ubicación:** `assets/img/`
- **Formato:** PNG con fondo transparente

**Ejemplo:**
```html
<div class="feature-card">
    <div class="feature-card-header">
        <img src="assets/img/feature-inventory.png" alt="Inventario" class="feature-card-image">
        <h3 class="feature-title">Gestión de Inventario</h3>
    </div>
    ...
</div>
```

**CSS para las imágenes:**
```css
.feature-card-image {
    width: 80px;
    height: 80px;
    object-fit: contain;
    margin-bottom: 15px;
}
```

---

### **4️⃣ Imágenes en Sección Demo**
- **Tamaño:** 300x250px
- **Descripción:** Captura de la ventana de demo
- **Ubicación:** `assets/img/demo-window.png`

---

## 🎨 Fuentes de Imágenes Gratuitas

### **Captura de Pantalla del Sistema:**
Si tienes FULLTECH POS instalado, puedes:
1. Abrirlo en tu computadora
2. Presionar `Print Screen` o `Cmd + Shift + 3` (Mac)
3. Editar la imagen en Paint o Photoshop
4. Guardar en `assets/img/` como PNG

### **Imágenes Diseñadas Profesionales:**
- **Figma:** https://figma.com (gratis)
- **Canva:** https://canva.com (plantillas gratis)
- **Unsplash:** https://unsplash.com (fotos gratis)
- **Pexels:** https://pexels.com (fotos gratis)

---

## 📝 Paso a Paso para Agregar una Imagen

### **Paso 1: Preparar la Imagen**
1. Abre tu imagen en editor (Photoshop, GIMP, Paint)
2. Redimensiona al tamaño recomendado
3. Exporta como PNG o JPG

### **Paso 2: Guardar en la Carpeta Correcta**
1. Abre `fulltech_pos_web/assets/img/`
2. Copia tu imagen aquí
3. Renómbrala de forma descriptiva (ej: `hero-dashboard.png`)

### **Paso 3: Actualizar HTML**
1. Abre `index.html` en VS Code
2. Busca dónde quieres la imagen
3. Reemplaza o agrega el `<img>` con la ruta correcta

### **Paso 4: Guardar y Verificar**
1. Guarda el archivo
2. Abre en el navegador (recarga con Ctrl+Shift+R)
3. Verifica que aparezca correctamente

---

## 📐 Tamaños Recomendados por Sección

| Sección | Ancho | Alto | Formato |
|---------|-------|------|---------|
| Logo | 120px | 120px | PNG |
| Hero Image | 400px | 400px | PNG/JPG |
| Feature Icons | 80px | 80px | PNG (transparente) |
| Demo Screenshot | 500px | 350px | PNG/JPG |
| Footer Icons | 24px | 24px | PNG (transparente) |

---

## 🔧 Optimización de Imágenes

### **Reducir Tamaño sin Perder Calidad:**
1. **Online:** https://tinypng.com o https://compressor.io
2. **Local:** ImageMagick, GIMP
3. Objetivo: Menos de 100KB por imagen

### **Formato Recomendado:**
- **Logos/Iconos:** PNG (fondo transparente)
- **Fotos/Screenshots:** JPG (mejor compresión)
- **Moderno:** WebP (mejor aún)

---

## 💡 Ejemplos de Imágenes a Agregar

### Opción 1: Minimalista (Sin imágenes extras)
- Solo logo
- Solo hero dashboard image
- No necesita más

### Opción 2: Profesional (Completo)
- Logo
- Hero dashboard
- Imágenes en tarjetas de características
- Captura de demo

### Opción 3: Premium (Diseño Completo)
- Logo
- Hero dashboard elegante
- Imágenes iconográficas en características
- Video en lugar de imagen estática
- Galería de screenshots

---

## 📞 Soporte

Si necesitas ayuda:
1. Verifica que la ruta en `src=""` sea correcta
2. Comprueba que el archivo exista en `assets/img/`
3. Recarga la página (Ctrl+Shift+R para limpiar caché)
4. Verifica la consola del navegador (F12) para errores

---

## 🚀 Próximos Pasos

Después de agregar imágenes:
1. Optimiza tamaños con TinyPNG
2. Prueba responsividad (F12, Device Toolbar)
3. Verifica que carguen rápido
4. Sube a servidor web

¡Listo! 🎉
