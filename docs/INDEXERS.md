# Indexers, Jackett y FlareSolverr

> Este documento cubre la parte que se sacó del video de YouTube sobre el stack.
> YouTube no explica exactamente qué clip infringe sus normas, así que la idea
> es dejar todo el setup detallado acá, en texto, donde sí se puede describir
> paso a paso sin ambigüedad.

Este doc asume que ya tenés el stack levantado (ver `README.md` → Inicio rápido).
Si Jackett y FlareSolverr están corriendo, seguimos.

---

## Por qué hablamos en URLs internas

Todos los servicios del stack comparten la red Docker `proxy`. Eso significa
que **adentro de la red, los containers se ven por nombre**. Si Radarr quiere
hablarle a Jackett, no tiene que salir a Internet ni pasar por Caddy: hace
`http://jackett:9117` y listo.

Esa es la URL que vamos a usar en todos lados:

| Desde | A Jackett | A FlareSolverr |
| --- | --- | --- |
| Desde tu navegador | `http://<tu-servidor>:9117` | `http://<tu-servidor>:8191` |
| Desde un *arr (Sonarr/Radarr) | `http://jackett:9117` | `http://flaresolverr:8191` |
| Desde Jackett hacia FlareSolverr | — | `http://flaresolverr:8191/` |

Si usás la URL externa (`<tu-servidor>:9117`) desde adentro de los *arr,
funciona también pero pasás por Caddy/red pública innecesariamente. La URL
interna es más rápida y no depende de que el proxy esté vivo.

---

## 1. Agregar indexers en Jackett

1. Abrí Jackett en `http://<tu-servidor>:9117`.
2. Si es la primera vez, te pide crear una contraseña de admin. **Anotala** —
   es la misma que después te va a pedir cada vez que entres.
3. Click en **+ Add Indexer**.
4. Buscá el tracker que querés agregar (hay cientos: 1337x, RARBG, YTS, etc.).
5. Click en él → se abre la pantalla de configuración:
   - **Configurar site**: si el tracker pide login (usuario y contraseña), llená
     los campos. Si es público, muchos no piden nada.
   - **Configurar Torznab**: podés setear capacidades extras (categorías,
     idioma, etc.). Para empezar dejá los defaults.
6. Click **OK** y volvés a la lista principal.

Probá que funcione haciendo click en el indexer que acabás de agregar. En la
lista de indexers, el ícono de estado a la izquierda tiene que estar verde.
Si está rojo/amarillo, mirá el JSON de respuesta que aparece abajo del botón
"Download Select" — ahí te dice qué se rompió.

### Cómo obtener el Torznab feed URL

Para cada indexer que quieras usar desde los *arr, necesitás la URL del feed
Torznab:

1. En la lista principal, buscá el indexer.
2. Click derecho sobre él → **Copy Feed URL** (o el botón "Copy" al lado del
   feed Torznab que aparece en la lista).
3. Te queda algo así:

   ```
   http://jackett:9117/api/v2.0/indexers/1337x/results/torznab/api?apikey=ABC123...
   ```

   Esa URL es la que después pegás en Sonarr/Radarr.

### API key de Jackett

La necesitás para que los *arr se autentiquen contra el feed. Está arriba a la
derecha en la UI de Jackett, en **Dashboard → API Key**. Es la misma para todos
los indexers, no es por-indexer.

---

## 2. Configurar FlareSolverr en Jackett

Muchos trackers importantes (1337x, RARBG, The Pirate Bay y un montón más)
ponen un **Cloudflare Challenge** delante. Sin algo que lo resuelva, Jackett
no puede bajar la página y parsear los resultados. Ahí entra FlareSolverr:
un proxy que usa un Chrome headless para resolver el challenge y devolverte
el HTML limpio.

> **TL;DR**: si tu indexer favorito falla con un error tipo "Cloudflare
> detected" o "403 Forbidden" en los logs de Jackett, este paso es lo que te
> falta.

### Configuración por indexer (lo recomendado)

1. En Jackett, click sobre el indexer que tiene el problema (no "Add Indexer"
   sino click en el existente).
2. Bajá hasta el final del formulario. Hay un selector que dice **FlareSolverr
   Proxy** con valores como `Disabled` y `FlareSolverr`.
3. Cambialo a **FlareSolverr**.
4. Aparece un campo para poner la URL. Poné:

   ```
   http://flaresolverr:8191/
   ```

   (Notá la barra al final, algunos trackers se quejan si no está.)
5. Click **OK** y volvé a probar el indexer.

### Configuración global (opcional)

Si querés que FlareSolverr esté prendido por default para todos los indexers
que lo soporten, podés setear la variable de entorno al levantar el container:

```yaml
# docker-compose.yml, en el servicio 'jackett'
environment:
  - FlareSolverrUrl=http://flaresolverr:8191/
```

Después reiniciá Jackett y los indexers nuevos van a usarlo por default. Los
que ya tenés configurados mantienen su config individual.

---

## 3. Configurar los indexers en Radarr y Sonarr

Ahora viene la parte que conecta todo. Para cada indexer que quieras usar en
Radarr (pelis) y Sonarr (series), repetís este procedimiento.

### En Sonarr (series)

1. Abrí Sonarr en `http://<tu-servidor>/sonarr`.
2. **Settings → Indexers → Add → Torznab** (no Prowlarr ni Newznab; el feed de
   Jackett es Torznab).
3. Llená el formulario:

   | Campo | Valor |
   | --- | --- |
   | **Name** | Lo que quieras (ej: `1337x via Jackett`). |
   | **Enable** | `ON` |
   | **URL** | El Torznab feed URL que copiaste de Jackett. **Tiene que empezar con `http://jackett:9117/...`**, no con `http://<tu-servidor>:9117/...`. Si tenés la URL pública, reemplazá la primera parte por `jackett:9117`. |
   | **API Key** | La API key de Jackett (Dashboard → API Key). |
   | **Categories** | `5000, 5020, 5030, 5040, 5045, 5050, 5060` (estándar para series; podés sumar/sacar). |
   | **Anime Categories** | `5070` si querés que aparezca anime en series. |
   | **Tags** | Dejá vacío por ahora. Lo de `flaresolverr` es solo si configuraste FlareSolverr como Indexer Proxy en el *arr (ver bonus más abajo), no es obligatorio. |
   | **Anime Standard Format Search** | `ON` solo si vas a usar anime. |

4. Click **Test**. Si dice "Test was successful", guardá.
5. Repetí para cada indexer que quieras tener disponible.

### En Radarr (pelis)

1. **Settings → Indexers → Add → Torznab**.
2. Mismos campos, con estos cambios:

   | Campo | Valor |
   | --- | --- |
   | **URL** | Igual: `http://jackett:9117/api/v2.0/indexers/.../torznab/...` |
   | **API Key** | La API key de Jackett. |
   | **Categories** | `2000, 2010, 2020, 2030, 2040, 2045, 2050, 2060` (pelis, incluidas HD y UHD). |
   | **Tags** | Dejá vacío. |

3. **Test** y guardá.

---

## Bonus: FlareSolverr como Indexer Proxy en el *arr

En lugar de configurar FlareSolverr adentro de Jackett, podés configurarlo en
el *arr como Indexer Proxy. Las dos formas funcionan; este approach tiene la
ventaja de que todos los indexers configurados como Torznab se benefician del
proxy sin tener que tocar cada uno, y la desventaja de que el *arr tiene que
esperar que FlareSolverr resuelva el challenge antes de pedirle los resultados
a Jackett (un round trip más).

Si querés ir por esta vía:

1. En el *arr: **Settings → Indexer Proxies → Add → FlareSolverr**.
2. **Host**: `flaresolverr` (el nombre del container en la red `proxy`).
3. **Port**: `8191`.
4. **URL Base**: dejá vacío.
5. Click **Save**. Te lleva al paso de **Tags** — ahí tildá todos los indexers
   que quieras que pasen por el proxy.
6. Cada indexer que tildaste hereda la config y va a usar FlareSolverr para
   los challenges.

> **Mi recomendación**: configurá FlareSolverr en Jackett (sección 2 de este
> doc). Es más simple, más rápido, y los challenges se resuelven una vez y
> quedan cacheados para todos los indexers que pidan lo mismo. El approach
> del *arr como Indexer Proxy es útil solo si tenés indexers que no están
> adentro de Jackett (tipo Prowlarr o Newznab directos).

---

## Troubleshooting

- **"Test was successful" pero las búsquedas devuelven 0 resultados.** El indexer
  funciona pero no tiene feeds para lo que buscás. Probá con algo popular (un
  release conocido) para descartar.
- **Los indexers marcados en verde en Jackett fallan en el *arr.** Casi siempre
  es que pegaste la URL externa (`http://<tu-servidor>:9117/...`) en vez de la
  interna (`http://jackett:9117/...`). Editá el indexer y corregila.
- **Error "401 Unauthorized" en los indexers del *arr.** La API key de Jackett
  está mal copiada o regenerada. Volvé a copiarla del Dashboard de Jackett.
- **Jackett no responde a `http://jackett:9117` desde el *arr.** Los dos
  containers tienen que estar en la misma red Docker. Acá lo están (red
  `proxy`), así que si falla es que algo custom lo rompió. Verificá con
  `docker inspect <container> | grep Networks`.
- **Cloudflare challenge sigue sin resolverse después de configurar
  FlareSolverr.** Logs: `docker logs flaresolverr`. Si ves errores de Chrome
  headless, puede ser que el container no tenga suficiente RAM (FlareSolverr
  levanta un Chromium real, pide ~300-500 MB por request). Sumá RAM al host o
  bajá la concurrencia de indexers.
- **Jackett devuelve error "Indexer download error: Connection refused".** El
  servicio de FlareSolverr no está corriendo o está en otra red. Verificá con
  `docker compose ps flaresolverr`.
