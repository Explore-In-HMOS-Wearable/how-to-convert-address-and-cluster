import { site, mapCommon } from '@kit.MapKit';
import { BusinessError } from '@kit.BasicServicesKit';
import { common } from '@kit.AbilityKit';
import { hilog } from '@kit.PerformanceAnalysisKit';

const TAG: string = 'ReverseGeocode';
const DOMAIN: number = 0x0000;

/**
 * One line of the flattened address, e.g. { label: 'Locality', value: 'Shenzhen' }.
 */
export interface AddressField {
  label: string;
  value: string;
}

/**
 * A point of interest returned next to the queried coordinate.
 */
export interface PoiItem {
  name: string;
  poiType: string;
  address: string;
  distance: string;
  direction: string;
  siteId: string;
  location: string;
}

/**
 * An area of interest (campus, park, mall...) the queried coordinate falls in or near.
 */
export interface AoiItem {
  name: string;
  poiType: string;
  area: string;
  distance: string;
  direction: string;
  siteId: string;
  location: string;
}

export interface ReverseGeocodeView {
  description: string;
  fields: AddressField[];
  pois: PoiItem[];
  aois: AoiItem[];
}

export interface ReverseGeocodeOutcome {
  ok: boolean;
  message: string;
  data: ReverseGeocodeView;
}

const EMPTY_VIEW: ReverseGeocodeView = { description: '', fields: [], pois: [], aois: [] };

function textOf(value: string | undefined): string {
  return value !== undefined && value.length > 0 ? value : '-';
}

function distanceOf(value: number | undefined): string {
  return value !== undefined ? `${Math.round(value)} m` : '-';
}

function areaOf(value: number | undefined): string {
  return value !== undefined ? `${Math.round(value)} m2` : '-';
}

function latLngOf(value: mapCommon.LatLng | undefined): string {
  return value !== undefined ? `${value.latitude.toFixed(6)}, ${value.longitude.toFixed(6)}` : '-';
}

/**
 * Optional field: skipped entirely when the server did not return it, to keep the list
 * short on a watch face.
 */
function push(fields: AddressField[], label: string, value: string | undefined): void {
  if (value !== undefined && value.length > 0) {
    fields.push({ label: label, value: value });
  }
}

/**
 * Always-visible field. The city-bearing fields are rendered even when empty, otherwise a
 * missing city is indistinguishable from a field that was never requested: the row simply
 * would not exist and there is nothing on screen to debug.
 */
function pushAlways(fields: AddressField[], label: string, value: string | undefined): void {
  const present: boolean = value !== undefined && value.length > 0;
  fields.push({ label: label, value: present ? value as string : '(empty)' });
}

/**
 * AddressComponent is a bag of optional fields: a level is absent whenever the queried
 * coordinate has no such administrative division. Read it defensively and keep only the
 * levels that actually came back.
 */
export function extractAddressFields(component: site.AddressComponent): AddressField[] {
  const fields: AddressField[] = [];

  pushAlways(fields, 'Country', component.countryName);
  push(fields, 'Country code', component.countryCode);

  // adminLevel1..5 run from the largest division (state / province) down to the smallest
  // division that the country defines, and most countries only fill the first two.
  // Depending on the country, the city name lands in adminLevel1, adminLevel2, locality
  // or city.cityName, so all four are shown unconditionally.
  pushAlways(fields, 'Admin level 1', component.adminLevel1);
  pushAlways(fields, 'Admin level 2', component.adminLevel2);
  push(fields, 'Admin level 3', component.adminLevel3);
  push(fields, 'Admin level 4', component.adminLevel4);
  push(fields, 'Admin level 5', component.adminLevel5);
  push(fields, 'Admin code', component.adminCode);

  pushAlways(fields, 'Locality', component.locality);
  push(fields, 'Sub locality 1', component.subLocality1);
  push(fields, 'Sub locality 2', component.subLocality2);
  push(fields, 'Postal code', component.postalCode);

  const neighborhoods: Array<string> | undefined = component.neighborhoods;
  if (neighborhoods !== undefined && neighborhoods.length > 0) {
    push(fields, 'Neighborhoods', neighborhoods.join(', '));
  }

  // city is a nested object, not a plain string: reading component.city directly as text
  // yields nothing. When the whole object is missing, say so rather than drawing no row.
  const city: site.City | undefined = component.city;
  if (city !== undefined) {
    pushAlways(fields, 'City', city.cityName);
    push(fields, 'City code', city.cityCode);
    push(fields, 'City id', city.cityId);
  } else {
    fields.push({ label: 'City', value: '(no city object)' });
  }

  // streetNumber carries the door number plus its own formatted address and the offset
  // between the queried point and that door.
  const streetNumber: site.StreetNumber | undefined = component.streetNumber;
  if (streetNumber !== undefined) {
    push(fields, 'Street', streetNumber.streetName);
    push(fields, 'Street number', streetNumber.streetNumber);
    push(fields, 'Street address', streetNumber.formatAddress);
    if (streetNumber.distance !== undefined) {
      push(fields, 'Street distance', distanceOf(streetNumber.distance));
    }
    push(fields, 'Street direction', streetNumber.direction);
    if (streetNumber.location !== undefined) {
      push(fields, 'Street location', latLngOf(streetNumber.location));
    }
  }

  return fields;
}

/**
 * POIs only arrive when the request sets isExtension = true.
 */
export function extractPois(pois: Array<site.ReverseGeocodePoi> | undefined): PoiItem[] {
  if (pois === undefined) {
    return [];
  }
  return pois.map((poi: site.ReverseGeocodePoi): PoiItem => {
    return {
      name: textOf(poi.name),
      poiType: textOf(poi.poiType),
      address: textOf(poi.address),
      distance: distanceOf(poi.distance),
      direction: textOf(poi.direction),
      siteId: textOf(poi.siteId),
      location: latLngOf(poi.location)
    };
  });
}

/**
 * AOIs only arrive when the request sets isNearbyAoi = true. Unlike a POI an AOI covers a
 * surface, so it reports an area; distance is 0 when the queried point is inside it.
 */
export function extractAois(aois: Array<site.Aoi> | undefined): AoiItem[] {
  if (aois === undefined) {
    return [];
  }
  return aois.map((aoi: site.Aoi): AoiItem => {
    return {
      name: textOf(aoi.name),
      poiType: textOf(aoi.poiType),
      area: areaOf(aoi.area),
      distance: distanceOf(aoi.distance),
      direction: textOf(aoi.direction),
      siteId: textOf(aoi.siteId),
      location: latLngOf(aoi.location)
    };
  });
}

function describeError(err: BusinessError): string {
  switch (err.code) {
    case 401:
      return 'Invalid input parameter: latitude must be in [-90, 90] and longitude in [-180, 180].';
    case 1002600001:
      return 'System internal error.';
    case 1002600002:
      return 'Failed to connect to the Map Kit server: check the network and ohos.permission.INTERNET.';
    case 1002600003:
      return 'App authentication failed: register the app in AGC with Map Kit enabled and sign it with that profile.';
    case 1002600004:
      return 'The Map permission is not enabled for this app in AGC.';
    case 1002603001:
      return 'Zero result: no address was found around this coordinate.';
    default:
      return `Reverse geocoding failed (${err.code}): ${err.message}`;
  }
}

/**
 * Turns a coordinate into an address plus the POIs and AOIs around it.
 *
 * radius bounds the search around the point; isExtension asks for the POI list and
 * isNearbyAoi for the AOI list. Both flags default to false, so an address-only caller can
 * leave them out and get a smaller payload back.
 */
export async function reverseGeocode(context: common.Context, location: mapCommon.LatLng,
  radius: number = 1000, language: string = 'en'): Promise<ReverseGeocodeOutcome> {
  const params: site.ReverseGeocodeParams = {
    location: location,
    radius: radius,
    language: language,
    isExtension: true,
    isNearbyAoi: true,
    sortRule: site.SortRule.DISTANCE
  };

  try {
    const result: site.ReverseGeocodeResult = await site.reverseGeocode(context, params);

    // Dump the untouched payload: if a name is missing on screen, this tells you whether
    // the server omitted it or the extraction dropped it.
    hilog.info(DOMAIN, TAG, 'raw addressComponent: %{public}s',
      JSON.stringify(result.addressComponent));
    hilog.info(DOMAIN, TAG, 'description=%{public}s pois=%{public}d aois=%{public}d',
      result.addressDescription, result.pois?.length ?? 0, result.aois?.length ?? 0);

    const view: ReverseGeocodeView = {
      // addressDescription is the ready-made single line; addressComponent is the same
      // address split into parts, for when you need one of them on its own.
      description: textOf(result.addressDescription),
      fields: extractAddressFields(result.addressComponent),
      pois: extractPois(result.pois),
      aois: extractAois(result.aois)
    };
    return { ok: true, message: '', data: view };
  } catch (error) {
    const err = error as BusinessError;
    return { ok: false, message: describeError(err), data: EMPTY_VIEW };
  }
}
