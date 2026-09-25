const DIAS = ["dom", "lun", "mar", "mié", "jue", "vie", "sáb"] as const;

export function zonaDePais(pais: string | null | undefined): string {
  return pais === "Perú" ? "America/Lima" : "America/Santiago";
}

export function formatearDia(iso: string): string {
  const [anio, mes, dia] = iso.slice(0, 10).split("-").map(Number);
  const fecha = new Date(Date.UTC(anio, mes - 1, dia));
  const nombre = DIAS[fecha.getUTCDay()];
  const dd = String(dia).padStart(2, "0");
  const mm = String(mes).padStart(2, "0");
  return `${nombre} ${dd}-${mm}-${anio}`;
}

export function formatearHora(hora: string | null | undefined): string {
  if (!hora) return "";
  return hora.slice(0, 5);
}

export type RangoEvento = {
  nombre: string;
  fecha: string;
  duracionDias: number;
  horaInicio: string | null;
  horaFin: string | null;
  lugar: string;
  direccion: string;
  descripcion: string;
};

function compactarFecha(iso: string): string {
  return iso.slice(0, 10).replaceAll("-", "");
}

function sumarDias(iso: string, dias: number): string {
  const [anio, mes, dia] = iso.slice(0, 10).split("-").map(Number);
  const fecha = new Date(Date.UTC(anio, mes - 1, dia + dias));
  const y = fecha.getUTCFullYear();
  const m = String(fecha.getUTCMonth() + 1).padStart(2, "0");
  const d = String(fecha.getUTCDate()).padStart(2, "0");
  return `${y}-${m}-${d}`;
}

function horaCompacta(hora: string): string {
  return hora.slice(0, 5).replace(":", "") + "00";
}

export function linksCalendario(evento: RangoEvento): {
  google: string;
  outlook: string;
} {
  const fin = sumarDias(evento.fecha, Math.max(evento.duracionDias, 1) - 1);
  const ubicacion = [evento.direccion, evento.lugar].filter(Boolean).join(", ");
  const tieneHoras = Boolean(evento.horaInicio && evento.horaFin);
  const text = encodeURIComponent(evento.nombre);
  const details = encodeURIComponent(evento.descripcion);
  const location = encodeURIComponent(ubicacion);

  if (!tieneHoras) {
    const finExclusivo = sumarDias(fin, 1);
    return {
      google:
        `https://calendar.google.com/calendar/render?action=TEMPLATE&text=${text}&dates=${
          compactarFecha(evento.fecha)
        }/${compactarFecha(finExclusivo)}&details=${details}&location=${location}`,
      outlook:
        `https://outlook.live.com/calendar/0/deeplink/compose?path=/calendar/action/compose&rru=addevent&subject=${text}&startdt=${
          evento.fecha.slice(0, 10)
        }&enddt=${finExclusivo}&allday=true&body=${details}&location=${location}`,
    };
  }

  const inicio = `${compactarFecha(evento.fecha)}T${horaCompacta(evento.horaInicio!)}`;
  const termino = `${compactarFecha(fin)}T${horaCompacta(evento.horaFin!)}`;
  const startDt = `${evento.fecha.slice(0, 10)}T${evento.horaInicio!.slice(0, 5)}:00`;
  const endDt = `${fin.slice(0, 10)}T${evento.horaFin!.slice(0, 5)}:00`;
  return {
    google:
      `https://calendar.google.com/calendar/render?action=TEMPLATE&text=${text}&dates=${inicio}/${termino}&details=${details}&location=${location}`,
    outlook:
      `https://outlook.live.com/calendar/0/deeplink/compose?path=/calendar/action/compose&rru=addevent&subject=${text}&startdt=${startDt}&enddt=${endDt}&body=${details}&location=${location}`,
  };
}
