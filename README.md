# Horda Cero

Shooter de zombis con vista cenital (twin-stick) para Android, hecho en Godot 4.
Todo se genera por código al arrancar: texturas con mapas de normales, sonidos y la ciudad.
No hay archivos de imagen ni de audio externos.

## Cómo conseguir el APK
Cada push compila el APK automáticamente con GitHub Actions:
pestaña **Actions** → última ejecución de "Compilar APK" → **Artifacts** → `HordaCero-apk`.
Descomprime el ZIP descargado e instala `HordaCero.apk` en el móvil (hay que permitir
"instalar apps de origen desconocido").

Para abrirlo en el editor: abre `juego/project.godot` con Godot 4.7 (o 4.3 o superior).

## Mecánicas
- **Desmembramiento:** cada impacto alcanza una parte concreta del infectado.
  - Sin un brazo pega más flojo; sin los dos, solo muerde.
  - Sin una pierna cojea; sin las dos se arrastra (y deja un rastro de sangre).
  - Sin cabeza muere al instante.
- **Ruido:** cada disparo despierta a los infectados cercanos (se ven las ondas de sonido)
  y llena el medidor de **RUIDO**. Si se llena, llega una horda desde los bordes de la ciudad.
  - La **ballesta** (atraviesa a 3 enemigos) y el **machete** son silenciosos.
  - Apagar la **linterna** hace que te detecten más tarde, pero ves menos.
- **Señuelos:**
  - **Bengala:** atrae a los infectados durante unos segundos y luego pierden tu rastro.
  - **Bomba de tubo:** pita, los atrae a todos y explota.
  - **Coches con alarma** (parpadean en rojo): si les disparas, atraen a todos hacia el coche.
    Es una trampa o una distracción, según dónde estés.
- **Barriles explosivos**, que pueden explotar en cadena.
- **Oleadas** cada vez más duras. Entre oleada y oleada eliges **1 de 3 mejoras**
  (escopeta, fusil, silenciador, balas perforantes, carnicero, pirotecnia...).
- **Infectados:**
  - **Común**
  - **Corredor** (sudadera naranja, muy rápido)
  - **Hinchado** (explota en ácido)
  - **Chillón** (grita y llama a la horda: mátalo primero)
  - **Bruto** (enorme, carga contra ti; si choca contra un muro queda aturdido)
- Récord guardado en el móvil.

## Controles
**Táctil:**
- Mitad izquierda: joystick para moverte.
- Mitad derecha: joystick para apuntar. Dispara al empujarlo, con ayuda al apuntar.
- Botones: MACHETE, ESQUIVAR, BENGALA, BOMBA, ARMA, RECARGAR, LUZ y pausa
  (el botón "atrás" de Android también pausa).

**PC:**
- WASD: moverse.
- Ratón: apuntar y disparar.
- E o clic derecho: machete.
- Espacio: esquivar.
- R: recargar.
- Q o 1-4: cambiar de arma.
- F: bengala.
- G: bomba.
- L: linterna.
- Esc: pausa.

## Archivos
- `juego/scripts/main.gd`: ciudad, director de oleadas, ruido, balas, explosiones, sangre y restos.
- `juego/scripts/player.gd`: superviviente, armas, machete, esquiva y arrojadizos.
- `juego/scripts/zombie.gd`: infectados por partes, IA y desmembramiento.
- `juego/scripts/throwable.gd`: bengala, bomba de tubo y alarma de coche.
- `juego/scripts/tex.gd`: texturas procedurales con mapas de normales.
- `juego/scripts/hud.gd`: controles táctiles, interfaz y menús.
- `juego/scripts/fx.gd`: partículas ligeras.
- `juego/scripts/sfx.gd`: sonidos sintetizados.
- `legado/HordaCero-fps-prototipo.zip`: el prototipo anterior en primera persona.
