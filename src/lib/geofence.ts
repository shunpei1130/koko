// Public landmarks around the Imperial Palace. User coordinates stay inside this module.
const landmarks = [
  ['takebashi', 35.69065, 139.75675],
  ['hirakawamon', 35.68913, 139.75838],
  ['otemachi', 35.68574, 139.76054],
  ['nijubashi', 35.68047, 139.75942],
  ['sakuradamon', 35.67791, 139.75358],
  ['iwatabashi', 35.67694, 139.75660],
  ['hanzomon', 35.68548, 139.74477],
  ['chidorigafuchi', 35.69072, 139.74779],
] as const;

export type ZoneId = (typeof landmarks)[number][0];

export function nearestKokoZone(latitude: number, longitude: number): ZoneId | null {
  if (!Number.isFinite(latitude) || !Number.isFinite(longitude)) return null;
  const radians = Math.PI / 180;
  let zone: ZoneId | null = null;
  let nearest = 300;
  for (const [id, lat, lon] of landmarks) {
    const sinLat = Math.sin((lat - latitude) * radians / 2);
    const sinLon = Math.sin((lon - longitude) * radians / 2);
    const haversine = sinLat ** 2 + Math.cos(latitude * radians) * Math.cos(lat * radians) * sinLon ** 2;
    const metres = 12_742_000 * Math.asin(Math.sqrt(Math.min(1, haversine)));
    if (metres <= 300 && (zone === null || metres < nearest)) {
      zone = id;
      nearest = metres;
    }
  }
  return zone;
}

export function locateKokoZone(): Promise<ZoneId | null> {
  return new Promise((resolve, reject) => {
    if (!navigator.geolocation) {
      reject(new Error('location_unavailable'));
      return;
    }
    navigator.geolocation.getCurrentPosition(
      ({ coords }) => resolve(nearestKokoZone(coords.latitude, coords.longitude)),
      () => reject(new Error('location_unavailable')),
      { enableHighAccuracy: true, maximumAge: 0, timeout: 10_000 },
    );
  });
}
