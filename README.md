# KODIGO URBAN · Tienda estática + panel admin (v8)

## 1. Supabase
1. SQL Editor > New query > pega `schema.sql` > Run (se puede repetir sin problema).
2. Authentication > Users > Add user: tu correo y contraseña (marca "Auto confirm").
3. Authentication > Sign In / Providers > Email: desactiva "Allow new users to sign up".

## 2. GitHub
Sube TODO el contenido del ZIP a la raíz del repositorio (incluidas las carpetas `img/` con las fotos, el logo y la intro).
Settings > Pages > Deploy from a branch > main > / (root).

## 3. Panel
`tusitio/#admin` (o toca 5 veces el logo del pie de página). Pestañas:
Productos · Categorías · Banners · Apariencia (colores, logo, intro) · WhatsApp (números y destacado) · Pagos · Pedidos.

## 4. Avisos de pedidos por correo
Cada pedido envía un correo a kodigourban126@gmail.com (dirección, teléfono y productos del cliente).
La PRIMERA vez, el servicio de envío (FormSubmit) manda un correo de activación a esa dirección: ábrelo y pulsa "Activate".
Puedes cambiar el correo o probar el envío en el panel > Pagos > Aviso de pedidos por correo.
Con el panel abierto también suena y aparece una alerta cuando entra un pedido nuevo.

## 5. Enlaces de pago (pestaña "Enlaces de pago")
Ahí el dueño cambia, sin tocar código: el enlace de PayPal.me (la tienda le agrega sola el monto exacto), otro enlace de PayPal,
el enlace de Wompi de toda la tienda y los enlaces de CADA producto (con botones para aplicar el mismo enlace a todos o vaciarlos).
Al pagar con un enlace sin monto, el cliente ve el monto exacto en grande y se copia solo al tocar el botón de pago.

## 5b. Enlaces de pago por producto
En el panel, al crear o editar un producto, puedes pegar su enlace de PayPal y su enlace de Wompi (opcionales).
Los botones de PayPal y Wompi aparecen solos en todos los productos; sin enlace propio se usa el pago general con el monto exacto.

## 6. Pagos
Cada pedido se guarda con el total calculado por el servidor (precios reales de la base de datos).
Antes de marcar un pedido como pagado, compara su total con el pago recibido en PayPal o Wompi.


## Categorías
Al eliminar una categoría o subcategoría con productos, el panel muestra una advertencia; si el dueño confirma, los productos NO se borran: quedan sin categoría hasta que les elija otra.


## Botones de pago
Panel > Pagos > "Botones de pago": activa o quita PayPal y tarjetas (Wompi). Aplica en los productos, en el carrito y al finalizar la compra.

## Conexión con Supabase
La URL y la clave PUBLISHABLE (empieza con sb_publishable_) del proyecto vienen dentro de index.html. Si cambias de proyecto, ponlas en config.js. Un código con guiones (tipo 4474de12-…) NO es una clave.

