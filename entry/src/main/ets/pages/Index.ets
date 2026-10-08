import { mapCommon } from '@kit.MapKit';
import { common } from '@kit.AbilityKit';
import { hilog } from '@kit.PerformanceAnalysisKit';
import {
  AddressField,
  AoiItem,
  PoiItem,
  ReverseGeocodeOutcome,
  reverseGeocode
} from '../model/ReverseGeocodeService';

interface Preset {
  label: string;
  latitude: number;
  longitude: number;
}

const PRESETS: Preset[] = [
  { label: 'Ağrı', latitude: 39.721900, longitude: 43.056600 },
  { label: 'İstanbul', latitude: 41.008240, longitude: 28.978359 },
  { label: 'Paris', latitude: 48.858370, longitude: 2.294481 }
];

const EDGE: number = 28;

@Entry
@Component
struct Index {
  @State latitude: string = '39.721900';
  @State longitude: string = '43.056600';
  @State loading: boolean = false;
  @State errorText: string = '';
  @State queried: string = '';
  private requestId: number = 0;
  @State description: string = '';
  @State fields: AddressField[] = [];
  @State pois: PoiItem[] = [];
  @State aois: AoiItem[] = [];
  @Provide('pathStack') pathStack: NavPathStack = new NavPathStack();

  private context: common.UIAbilityContext = this.getUIContext()
    .getHostContext() as common.UIAbilityContext;

  async query(): Promise<void> {
    const lat: number = Number.parseFloat(this.latitude);
    const lng: number = Number.parseFloat(this.longitude);
    if (Number.isNaN(lat) || Number.isNaN(lng)) {
      this.errorText = 'Enter a numeric latitude and longitude.';
      return;
    }

    this.description = '';
    this.fields = [];
    this.pois = [];
    this.aois = [];
    this.errorText = '';
    this.loading = true;

    const location: mapCommon.LatLng = { latitude: lat, longitude: lng };

    this.queried = `${lat.toFixed(6)}, ${lng.toFixed(6)}`;
    hilog.info(0x0000, 'ReverseGeocode', 'querying %{public}s', this.queried);

    this.requestId += 1;
    const myRequest: number = this.requestId;

    const outcome: ReverseGeocodeOutcome = await reverseGeocode(this.context, location);

    if (myRequest !== this.requestId) {
      hilog.info(0x0000, 'ReverseGeocode', 'dropping stale response %{public}d', myRequest);
      return;
    }

    this.loading = false;
    this.description = outcome.data.description;
    this.fields = outcome.data.fields;
    this.pois = outcome.data.pois;
    this.aois = outcome.data.aois;
    this.errorText = outcome.ok ? '' : outcome.message;
  }

  @Builder
  sectionTitle(text: string) {
    Text(text)
      .fontSize(13)
      .fontColor('#7FB0FF')
      .fontWeight(FontWeight.Bold)
      .width('100%')
      .margin({ top: 14, bottom: 6 })
  }

  @Builder
  detailRow(label: string, value: string) {
    Column() {
      Text(label)
        .fontSize(11)
        .fontColor('#8A8A8A')
        .width('100%')
      Text(value)
        .fontSize(13)
        .fontColor('#FFFFFF')
        .width('100%')
    }
    .width('100%')
    .margin({ bottom: 6 })
  }

  @Builder
  card(title: string, rows: AddressField[], tint: string) {
    Column() {
      Text(title)
        .fontSize(13)
        .fontWeight(FontWeight.Medium)
        .fontColor(tint)
        .width('100%')
        .margin({ bottom: 4 })
      ForEach(rows, (row: AddressField) => {
        this.detailRow(row.label, row.value);
      }, (row: AddressField) => row.label)
    }
    .width('100%')
    .padding(10)
    .margin({ bottom: 8 })
    .backgroundColor('#1C1C1E')
    .borderRadius(12)
  }

  build() {
    Navigation(this.pathStack) {
      Scroll() {
        Column() {
          Text('Reverse geocode')
            .fontSize(16)
            .fontWeight(FontWeight.Bold)
            .fontColor('#FFFFFF')
            .margin({ top: 8, bottom: 10 })

          TextInput({ text: $$this.latitude, placeholder: 'Latitude' })
            .type(InputType.NUMBER_DECIMAL)
            .fontSize(13)
            .height(36)
            .width('100%')

          TextInput({ text: $$this.longitude, placeholder: 'Longitude' })
            .type(InputType.NUMBER_DECIMAL)
            .fontSize(13)
            .height(36)
            .width('100%')
            .margin({ top: 6 })

          Row() {
            ForEach(PRESETS, (preset: Preset) => {
              Button(preset.label)
                .fontSize(10)
                .backgroundColor('#2C2C2E')
                .fontColor('#CCCCCC')
                .height(26)
                .layoutWeight(1)
                .margin({ left: 2, right: 2 })
                .onClick(() => {
                  this.latitude = preset.latitude.toString();
                  this.longitude = preset.longitude.toString();
                })
            }, (preset: Preset) => preset.label)
          }
          .width('100%')
          .margin({ top: 8 })

          Button(this.loading ? 'Resolving...' : 'Convert to address')
            .fontSize(13)
            .height(36)
            .width('100%')
            .margin({ top: 8 })
            .enabled(!this.loading)
            .onClick(() => {
              this.query();
            })

          Button('Cluster demo')
            .fontSize(12)
            .backgroundColor('#2C2C2E')
            .fontColor('#7FB0FF')
            .height(30)
            .width('100%')
            .margin({ top: 6 })
            .onClick(() => {
              this.pathStack.pushPathByName('ClusterPage', null);
            })

          if (this.errorText.length > 0) {
            Text(this.errorText)
              .fontSize(12)
              .fontColor('#FF6B6B')
              .width('100%')
              .margin({ top: 10 })
          }

          if (this.queried.length > 0) {
            this.sectionTitle('Queried coordinate')
            Text(this.queried)
              .fontSize(12)
              .fontColor('#9FE08F')
              .width('100%')
          }

          if (this.description.length > 0) {
            this.sectionTitle('Address')
            Text(this.description)
              .fontSize(13)
              .fontColor('#FFFFFF')
              .width('100%')
          }

          if (this.fields.length > 0) {
            this.sectionTitle(`Address details (${this.fields.length})`)
            ForEach(this.fields, (field: AddressField) => {
              this.detailRow(field.label, field.value);
            }, (field: AddressField) => field.label)
          }

          if (this.pois.length > 0) {
            this.sectionTitle(`POIs nearby (${this.pois.length})`)
            ForEach(this.pois, (poi: PoiItem) => {
              this.card(poi.name, [
                { label: 'Type', value: poi.poiType },
                { label: 'Address', value: poi.address },
                { label: 'Distance', value: `${poi.distance} ${poi.direction}` },
                { label: 'Location', value: poi.location }
              ], '#7FB0FF');
            }, (poi: PoiItem) => `${poi.siteId}-${poi.name}-${poi.location}`)
          }

          if (this.aois.length > 0) {
            this.sectionTitle(`AOIs nearby (${this.aois.length})`)
            ForEach(this.aois, (aoi: AoiItem) => {
              this.card(aoi.name, [
                { label: 'Type', value: aoi.poiType },
                { label: 'Area', value: aoi.area },
                { label: 'Distance', value: `${aoi.distance} ${aoi.direction}` },
                { label: 'Location', value: aoi.location }
              ], '#9FE08F');
            }, (aoi: AoiItem) => `${aoi.siteId}-${aoi.name}-${aoi.location}`)
          }
          Blank().height(40)
        }
        .width('100%')
        .padding({ left: EDGE, right: EDGE })
      }
      .width('100%')
      .height('100%')
      .backgroundColor('#000000')
      .scrollBar(BarState.Auto)
      .edgeEffect(EdgeEffect.Spring)
    }
    .hideTitleBar(true)
    .mode(NavigationMode.Stack)
  }
}
