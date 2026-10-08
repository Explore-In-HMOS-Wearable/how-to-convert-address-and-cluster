import { MapComponent, mapCommon, map } from '@kit.MapKit';
import { AsyncCallback, BusinessError } from '@kit.BasicServicesKit';
import { hilog } from '@kit.PerformanceAnalysisKit';

const TAG: string = 'ClusterDemo';
const DOMAIN: number = 0x0000;

class PlaceItem extends mapCommon.ClusterItem {
  position: mapCommon.LatLng;
  name: string;
  poiType: string;

  constructor(latitude: number, longitude: number, name: string, poiType: string) {
    super();
    this.position = { latitude: latitude, longitude: longitude };
    this.name = name;
    this.poiType = poiType;
  }
}

interface EventLine {
  id: number;
  text: string;
}

const CITY: mapCommon.LatLng = { latitude: 39.721900, longitude: 43.056600 };

function buildItems(): PlaceItem[] {
  const items: PlaceItem[] = [];
  for (let i = 0; i < 40; i++) {
    const ring: number = 0.004 + (i % 5) * 0.010;
    const angle: number = (i * 37) % 360 * Math.PI / 180;
    items.push(new PlaceItem(
      CITY.latitude + ring * Math.sin(angle),
      CITY.longitude + ring * Math.cos(angle),
      `Place ${i + 1}`,
      i % 2 === 0 ? 'restaurant' : 'store'
    ));
  }
  return items;
}

@Builder
export function ClusterPageBuilder() {
  ClusterPage()
}

@Component
struct ClusterPage {
  @State tappedCount: number = 0;
  @State tappedNames: string = '';
  @State status: string = 'Loading map...';
  /**
   * Rolling tap-event log, newest first, so the firing order is visible on the device.
   * Tap events only: camera events are far too chatty for a watch panel and go to hilog.
   */
  @State events: EventLine[] = [];
  private nextEventId: number = 0;

  private controller: map.MapComponentController | undefined = undefined;
  private clusterOverlay: map.ClusterOverlay | undefined = undefined;
  private eventManager: map.MapEventManager | undefined = undefined;

  private log(source: string, detail: string): void {
    hilog.info(DOMAIN, TAG, '%{public}s %{public}s', source, detail);
    const line: EventLine = { id: this.nextEventId++, text: `${source}  ${detail}` };
    this.events = [line].concat(this.events).slice(0, 4);
  }

  private mapOptions: mapCommon.MapOptions = {
    position: { target: CITY, zoom: 12 },
    zoomControlsEnabled: false,
    scaleControlsEnabled: false
  };

  private mapCallback: AsyncCallback<map.MapComponentController> =
    async (err: BusinessError, controller: map.MapComponentController) => {
      if (err) {
        this.status = `Map failed: ${err.code} ${err.message}`;
        hilog.error(DOMAIN, TAG, 'map init failed %{public}s', JSON.stringify(err));
        return;
      }
      this.controller = controller;
      this.attachMapEvents(controller);
      await this.attachCluster();
    };

  attachMapEvents(controller: map.MapComponentController): void {
    const manager: map.MapEventManager = controller.getEventManager();
    this.eventManager = manager;

    manager.on('mapLoad', () => {
      this.log('mapLoad', 'tiles ready');
    });

    manager.on('mapClick', (position: mapCommon.LatLng) => {
      this.log('mapClick', `${position.latitude.toFixed(4)}, ${position.longitude.toFixed(4)}`);
    });

    manager.on('mapLongClick', (position: mapCommon.LatLng) => {
      this.log('mapLongClick', `${position.latitude.toFixed(4)}, ${position.longitude.toFixed(4)}`);
    });

    manager.on('poiClick', (poi: mapCommon.Poi) => {
      this.log('poiClick', `${poi.name} (${poi.id})`);
    });

    manager.on('markerClick', (marker: map.Marker) => {
      this.log('markerClick', marker.getTitle());
    });

    manager.on('cameraMoveStart', (reason: number) => {
      hilog.info(DOMAIN, TAG, 'cameraMoveStart reason=%{public}d', reason);
    });

    manager.on('cameraIdle', () => {
      hilog.info(DOMAIN, TAG, 'cameraIdle');
    });
  }

  async attachCluster(): Promise<void> {
    const controller: map.MapComponentController | undefined = this.controller;
    if (controller === undefined) {
      return;
    }

    try {
      const params: mapCommon.ClusterOverlayParams = {
        clusterItems: buildItems(),
        distance: 120
      };
      const overlay: map.ClusterOverlay = await controller.addClusterOverlay(params);
      this.clusterOverlay = overlay;

      overlay.on('markerClusterClick', (info: map.MarkerClusterInfo) => {
        const items: Array<mapCommon.ClusterItem> = info.clusterItems;
        const at: mapCommon.LatLng = info.marker.getPosition();
        this.log('markerClusterClick',
          `${items.length} items @ ${at.latitude.toFixed(4)}, ${at.longitude.toFixed(4)}`);
        this.showItems(items);
      });
      overlay.on('clusterClick', (items: Array<mapCommon.ClusterItem>) => {
        this.log('clusterClick', `${items.length} items (no marker)`);
      });

      this.status = 'Tap a bubble, then tap empty map';
    } catch (error) {
      const err = error as BusinessError;
      this.status = `Cluster failed: ${err.code} ${err.message}`;
      hilog.error(DOMAIN, TAG, 'addClusterOverlay failed %{public}s', JSON.stringify(err));
    }
  }

  showItems(items: Array<mapCommon.ClusterItem>): void {
    const names: string[] = [];
    items.forEach((item: mapCommon.ClusterItem) => {
      if (item instanceof PlaceItem) {
        const place: PlaceItem = item as PlaceItem;
        names.push(`${place.name} (${place.poiType})`);
      }
    });
    this.tappedCount = items.length;
    this.tappedNames = names.join(', ');
  }

  aboutToDisappear(): void {
    const overlay: map.ClusterOverlay | undefined = this.clusterOverlay;
    if (overlay !== undefined) {
      overlay.off('markerClusterClick');
      overlay.off('clusterClick');
      overlay.remove();
      this.clusterOverlay = undefined;
    }

    const manager: map.MapEventManager | undefined = this.eventManager;
    if (manager !== undefined) {
      manager.off('mapLoad');
      manager.off('mapClick');
      manager.off('mapLongClick');
      manager.off('poiClick');
      manager.off('markerClick');
      manager.off('cameraMoveStart');
      manager.off('cameraIdle');
      this.eventManager = undefined;
    }
  }

  build() {
    NavDestination() {
      Stack({ alignContent: Alignment.Bottom }) {
        MapComponent({ mapOptions: this.mapOptions, mapCallback: this.mapCallback })
          .width('100%')
          .height('100%')

        Column() {
          Text(this.status)
            .fontSize(12)
            .fontColor('#FFFFFF')
            .width('100%')

          if (this.tappedCount > 0) {
            Text(`${this.tappedCount} places in this cluster`)
              .fontSize(13)
              .fontWeight(FontWeight.Bold)
              .fontColor('#9FE08F')
              .width('100%')
              .margin({ top: 4 })
            Text(this.tappedNames)
              .fontSize(11)
              .fontColor('#CCCCCC')
              .maxLines(2)
              .textOverflow({ overflow: TextOverflow.Ellipsis })
              .width('100%')
              .margin({ top: 2 })
          }

          ForEach(this.events, (line: EventLine) => {
            Text(line.text)
              .fontSize(10)
              .fontColor(line.id === this.nextEventId - 1 ? '#9FE08F' : '#888888')
              .maxLines(1)
              .textOverflow({ overflow: TextOverflow.Ellipsis })
              .width('100%')
          }, (line: EventLine) => `${line.id}`)
        }
        .width('100%')
        .padding(12)
        .backgroundColor('#CC000000')
      }
      .width('100%')
      .height('100%')
    }
    .hideTitleBar(true)
  }
}
