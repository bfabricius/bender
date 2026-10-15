# Diagrammarten & Entscheidungshilfe

Der Agent wählt die Art **nicht allein**: Nennt der User keine Art, führe die Beratung unten durch.

## Übersicht

| Art | Zeigt | Typische Elemente | Layout-Muster | Wähle, wenn … |
|---|---|---|---|---|
| **Architektur (Schichten)** | Aufbau eines Systems in Layern/Komponenten | Layer-Container, Komponenten, Datenspeicher, Pfeile für Fluss | Vertikal gestapelte Layer, Komponenten im Grid | das «Was besteht woraus» und der Anfragefluss zählt (Lösungskonzept, Pflichtenheft) |
| **Infrastruktur / Deployment** | Wo was läuft (Cloud, Zonen, Server, Dienste) | Cloud-/Zonen-Grenze (boundary), VMs, Cluster, LB, Storage, DB | Verschachtelte Zonen: Region → Netz/Subnetz → Ressource | Hosting, BoM, Offertanfrage, Betrieb im Vordergrund stehen |
| **Netzwerk-/System-Topologie** | Verbindungen und Segmente zwischen Systemen | Netzsegmente, Gateways, Firewalls, VPN, Standorte | Zonen links→rechts (Internet → DMZ → intern), beschriftete Links | Netzwerktrennung, Zugriffspfade, Sicherheitszonen erklärt werden sollen |
| **Systemkontext / Integration** | System im Umfeld: Akteure und Nachbarsysteme | Zentrales System, externe Systeme, Akteure, Schnittstellen | Zentrum + Satelliten | Schnittstellen/Abhängigkeiten zu Drittsystemen (z. B. CMS, M365) gezeigt werden |
| **Datenfluss (DFD)** | Wie Daten durch Verarbeitungsschritte laufen | Quellen, Prozesse, Speicher, Senken | Links→rechts, Pfeile mit Datenbezeichnung | Datenschutz, Datenhaltung, Pipelines (z. B. Ingest → Parsing → Index) |
| **Prozess / Ablauf (Flowchart)** | Schritte, Entscheidungen, Verantwortliche | Start/Ende, Schritt, Entscheidung, Swimlanes | Top→down oder Swimlanes | Ablauf und Verantwortung wichtiger sind als Technik |
| **Sequenz** | Zeitliche Interaktion zwischen Komponenten | Lifelines, Nachrichten | Lifelines horizontal, Zeit vertikal | Reihenfolge von Aufrufen (API, Auth) – *Hinweis: build_drawio.py unterstützt das nicht, siehe style-guide* |
| **Organisation / Rollen** | Hierarchie, Gremien, Projektorganisation | Rollen-Boxen, Linien | Baum top→down | Projektorganisation/Stakeholder |
| **Roadmap / Phasen** | Zeitliche Abfolge von Phasen | Phasen-Chevrons, Meilensteine | Links→rechts | Vorgehen/Meilensteine (Alternative: Master-Schedule im Projekt) |

## Beratungs-Dialog (wenn Art unklar)

Stelle **max. 3–4 Fragen** gebündelt per `ask_user`, dann schlage **1–2 Arten mit Begründung** vor.

1. **Kernfrage des Diagramms** (Einfach-Auswahl):
   - «Wie ist das System aufgebaut?» → Architektur
   - «Wo und auf welcher Infrastruktur läuft es?» → Infrastruktur/Deployment
   - «Wie sind Netze/Zonen verbunden und abgesichert?» → Netzwerk-Topologie
   - «Mit wem spricht das System?» → Systemkontext
   - «Wie wandern die Daten?» → Datenfluss
   - «Welche Schritte/Rollen gibt es?» → Prozess
2. **Zielpublikum:** Management/Entscheider (grob, wenige Boxen) · technisch (Details, Produktnamen) · Auditoren/Einkauf (Zonen, Standort, Compliance)?
3. **Verwendung:** Offerte/Dokument (A4-quer, statisch, lesbar bei 100 %) · Workshop (editierbar) · Präsentation (grosszügig, grosse Schrift)?
4. **Detailgrad:** Überblick (≤ 10 Elemente) · Standard (10–25) · Detail (> 25 → in mehrere Diagramme/Seiten teilen).

### Entscheidungsregeln (Vorschlag)
- Input nennt Layer/Schichten, Komponenten, Flow → **Architektur**.
- Input nennt Regionen, Zonen, VMs, Kubernetes, Storage, SLA → **Infrastruktur/Deployment**.
- Input betont DMZ, VPN, Firewall, Subnetze → **Netzwerk-Topologie** (oder Infrastruktur mit Netzfokus).
- Mischfälle (z. B. Layer **und** Netzsegmente): **eine** Hauptart wählen, die andere als Farbe/Container-Zusatz
  abbilden (z. B. Architektur mit DMZ-/Intern-Subnetzen als Container) – nicht beides in ein Bild pressen.
- Bleibt es unklar: 2 Varianten kurz skizzieren (Elementliste + Layout in 2–3 Sätzen) und User wählen lassen.

## Layout-Konventionen je Art

- **Architektur:** Flussrichtung oben→unten (Benutzer/Internet oben, Daten unten); pro Layer eine Farbe; max. 4–5 Komponenten pro Zeile.
- **Infrastruktur:** äusserste `boundary` = Provider/Standort (z. B. «Standort Schweiz»), darin Zonen/Netze, darin Ressourcen. Speicher/Datenbanken als `database`.
- **Netzwerk:** Vertrauensgrad steigt von links/oben (Internet, rot) nach innen (grün/grau); Verbindungen mit Protokoll/Tunnel beschriften (HTTPS, IPSec-VPN); VPN gestrichelt.
- **Kontext:** Systeminhalt zentral, Akteure `actor` links, Nachbarsysteme `external` rechts/unten.
- **Datenfluss:** Pfeilbeschriftung = übertragene Daten; Speicher `database`.
- **Prozess:** Entscheidungen als Raute (manuelle XML-Variante, siehe style-guide), «Ja/Nein» an Kanten.
