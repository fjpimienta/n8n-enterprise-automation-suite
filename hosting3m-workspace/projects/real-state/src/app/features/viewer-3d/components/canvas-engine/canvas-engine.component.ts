import { GLTFLoader } from 'three/examples/jsm/loaders/GLTFLoader.js';
import { Component, ElementRef, NgZone, OnDestroy, OnInit, viewChild, inject, input, AfterViewInit } from '@angular/core';
import { ThreeStateService } from '../../services/three-state';
import * as THREE from 'three';
import { OrbitControls } from 'three/examples/jsm/controls/OrbitControls.js';
import { DRACOLoader } from 'three/examples/jsm/loaders/DRACOLoader.js';
import { Subscription } from 'rxjs';
import { RGBELoader } from 'three/examples/jsm/loaders/RGBELoader.js';

@Component({
  selector: 'app-canvas-engine',
  standalone: true,
  template: `
    <div #rendererContainer class="canvas-container">
      @if (threeState.isModelLoading()) {
        <div class="loader-overlay">
          <p style="font-size: 1.25rem; font-weight: bold; margin-bottom: 0.5rem;">Renderizando Desarrollo...</p>
          <p style="color: #ccc;">{{ threeState.loadingProgress() }}%</p>
        </div>
      }
      
      @if (selectedObjectName) {
        <div class="info-panel">
          Componente seleccionado: <strong>{{ selectedObjectName }}</strong>
        </div>
      }
    </div>
  `,
  styles: [`
    :host { display: block; width: 100vw; height: 100vh; overflow: hidden; margin: 0; padding: 0; }
    .canvas-container { width: 100%; height: 100%; background-color: #1e1e2f; position: relative; }
    .loader-overlay { position: absolute; inset: 0; background-color: rgba(0, 0, 0, 0.85); color: white; display: flex; flex-direction: column; align-items: center; justify-content: center; z-index: 10; font-family: sans-serif; }
    
    /* Estilo del panel de selección */
    .info-panel {
      position: absolute;
      bottom: 20px;
      left: 50%;
      transform: translateX(-50%);
      background: rgba(255, 255, 255, 0.9);
      padding: 10px 20px;
      border-radius: 8px;
      font-family: sans-serif;
      color: #333;
      pointer-events: none; /* Para que no bloquee los clics al canvas */
      box-shadow: 0 4px 6px rgba(0,0,0,0.3);
    }
  `]
})
export class CanvasEngineComponent implements AfterViewInit, OnDestroy {
  modelUrl = input.required<string>();
  rendererContainer = viewChild.required<ElementRef<HTMLDivElement>>('rendererContainer');

  private ngZone = inject(NgZone);

  public threeState = inject(ThreeStateService);
  private subscriptions: Subscription = new Subscription();

  private houseModel!: THREE.Group;
  private originalMaterials: Map<string, THREE.Material> = new Map();
  // Plano de corte apuntando hacia abajo (eje Y negativo). El valor 3.0 es la altura en metros.
  private clipPlane = new THREE.Plane(new THREE.Vector3(0, -1, 0), 3.0);

  private scene!: THREE.Scene;
  private camera!: THREE.PerspectiveCamera;
  private renderer!: THREE.WebGLRenderer;
  private controls!: OrbitControls;
  private animationFrameId: number | null = null;

  // --- 1. Variables Core para el Raycaster ---
  private raycaster = new THREE.Raycaster();
  private pointer = new THREE.Vector2();
  private modelGroup: THREE.Group | null = null; // Guardamos referencia del modelo cargado
  private previousSelectedMesh: THREE.Mesh | null = null; // Para quitarle el brillo al anterior
  protected selectedObjectName: string | null = null; // Variable local para la UI

  // CAMBIO 1: Reemplazar ngOnInit por ngAfterViewInit
  ngAfterViewInit(): void {
    this.initEngine();
    this.loadDevelopmentModel(this.modelUrl());
    this.setupReactiveListeners(); // Faltaba inicializar las suscripciones
  }

  // CAMBIO 2: Proteger el ngOnDestroy contra nulos
  ngOnDestroy(): void {
    this.subscriptions.unsubscribe();

    const domElement = this.rendererContainer().nativeElement;
    domElement.removeEventListener('pointerdown', this.onPointerDown.bind(this));
    window.removeEventListener('resize', this.onWindowResize.bind(this));

    if (this.animationFrameId) cancelAnimationFrame(this.animationFrameId);

    if (this.scene) {
      this.scene.traverse((object: any) => {
        if (object.isMesh) {
          object.geometry.dispose();
          if (object.material.isMaterial) object.material.dispose();
          else if (Array.isArray(object.material)) object.material.forEach((m: any) => m.dispose());
        }
      });
    }

    // Validar que el renderer exista antes de destruirlo
    if (this.renderer) {
      this.renderer.dispose();
    }
  }

  private setupReactiveListeners(): void {
    // Escuchar cambios de Rayos X
    this.subscriptions.add(
      this.threeState.xrayMode$.subscribe(enabled => this.applyXRay(enabled))
    );

    // Escuchar cambios de Piso
    this.subscriptions.add(
      this.threeState.currentFloor$.subscribe(floor => this.sliceArchitecture(floor))
    );
  }

  private applyXRay(enabled: boolean): void {
    if (!this.houseModel) return;

    this.houseModel.traverse((child: any) => {
      if (child.isMesh && child.material) {
        if (enabled) {
          child.material.transparent = true;
          child.material.opacity = 0.25; // 75% de transparencia
          child.material.needsUpdate = true;
        } else {
          // Restaurar el material original fotorrealista
          const original = this.originalMaterials.get(child.uuid);
          if (original) {
            child.material.transparent = original.transparent;
            child.material.opacity = original.opacity;
            child.material.needsUpdate = true;
          }
        }
      }
    });
  }

  private sliceArchitecture(floor: string): void {
    if (!this.houseModel) return;

    this.houseModel.traverse((child: any) => {
      if (child.isMesh && child.material) {
        if (floor === 'planta-baja') {
          // Asigna el plano de corte al material (Corta todo lo que esté por encima de 3 metros)
          child.material.clippingPlanes = [this.clipPlane];
        } else {
          // Limpia el plano de corte para mostrar el modelo completo
          child.material.clippingPlanes = null;
        }
        child.material.needsUpdate = true;
      }
    });
  }



  private initEngine(): void {
    const container = this.rendererContainer().nativeElement;

    this.scene = new THREE.Scene();
    this.camera = new THREE.PerspectiveCamera(45, container.clientWidth / container.clientHeight, 0.1, 2000);

    // 1. CAMBIO CRÍTICO: Acercamos la cámara (Ej. 10m a la derecha, 5m de altura, 15m hacia atrás)
    this.camera.position.set(10, 5, 15);

    this.renderer = new THREE.WebGLRenderer({ antialias: true, alpha: false, powerPreference: "high-performance" });
    this.renderer.localClippingEnabled = true;
    this.renderer.setSize(container.clientWidth, container.clientHeight);
    this.renderer.setPixelRatio(Math.min(window.devicePixelRatio, 2));

    this.renderer.toneMapping = THREE.ACESFilmicToneMapping;
    this.renderer.toneMappingExposure = 1.0;

    container.appendChild(this.renderer.domElement);

    this.controls = new OrbitControls(this.camera, this.renderer.domElement);
    this.controls.enableDamping = true;
    this.controls.dampingFactor = 0.05;

    // 2. CAMBIO CRÍTICO: Aseguramos que el usuario orbite alrededor del centro exacto del departamento
    this.controls.target.set(0, 0, 0);

    // Quitamos las luces artificiales (AmbientLight y DirectionalLight). 
    // ¡La luz ahora provendrá de la fotografía 360° del cuarto!

    // Luz de relleno temporal
    const dirLight = new THREE.DirectionalLight(0xffffff, 1);
    dirLight.position.set(10, 20, 10);
    this.scene.add(dirLight);

    // Cargar el cuarto virtual antes de cargar el modelo del edificio
    this.loadVirtualShowroom();

    this.renderer.domElement.addEventListener('pointerdown', this.onPointerDown.bind(this));
    window.addEventListener('resize', this.onWindowResize.bind(this));

    this.ngZone.runOutsideAngular(() => this.animate());
  }

  private loadVirtualShowroom(): void {
    const hdrLoader = new RGBELoader();

    // Validar que la ruta coincida matemáticamente con la carpeta física
    const showroomUrl = 'assets/environments/urban_courtyard_02_2k.hdr';

    hdrLoader.load(showroomUrl, (texture) => {
      texture.mapping = THREE.EquirectangularReflectionMapping;

      // Asignamos el HDR al fondo y a la iluminación global de la escena
      this.scene.background = texture;
      this.scene.environment = texture;

      console.log('HDR urban_courtyard cargado exitosamente. Iluminación IBL activa.');
    }, undefined, (error) => {
      console.error('Fallo en la carga del HDR. Revisa el peso del archivo y la ruta:', error);
    });
  }

  private loadDevelopmentModel(url: string): void {
    this.threeState.setLoading(true);

    // 1. Instanciar el decodificador WebAssembly de Draco
    const dracoLoader = new DRACOLoader();
    // Apuntamos al CDN oficial para no sobrecargar nuestro repositorio local
    dracoLoader.setDecoderPath('https://www.gstatic.com/draco/versioned/decoders/1.5.6/');

    // 2. Instanciar el GLTFLoader y acoplarle el decodificador
    const loader = new GLTFLoader();
    loader.setDRACOLoader(dracoLoader);

    loader.load(
      url,
      (gltf) => {
        this.modelGroup = gltf.scene;

        const box = new THREE.Box3().setFromObject(this.modelGroup);
        const center = box.getCenter(new THREE.Vector3());
        this.modelGroup.position.sub(center);

        this.scene.add(this.modelGroup);
        this.ngZone.run(() => this.threeState.setLoading(false));

        // Liberar memoria del decodificador una vez que el modelo ya se infló en la GPU
        dracoLoader.dispose();
      },
      (xhr) => {
        if (xhr.lengthComputable) {
          const percent = Math.round((xhr.loaded / xhr.total) * 100);
          this.ngZone.run(() => this.threeState.updateProgress(percent));
        }
      },
      (error) => {
        console.error('Error WebGL Loader:', error);
        this.ngZone.run(() => this.threeState.setLoading(false));
      }
    );
  }

  // --- 3. Lógica Matemática del Raycaster ---
  private onPointerDown(event: PointerEvent): void {
    if (!this.modelGroup) return; // Si el modelo no ha cargado, no hacemos nada

    // Evitar detectar clics si estamos rotando la cámara (OrbitControls)
    // Generalmente un clic primario (izquierdo o touch simple) sin arrastrar es lo que queremos.
    if (event.button !== 0) return;

    const container = this.rendererContainer().nativeElement;
    const rect = container.getBoundingClientRect();

    // Normalizar coordenadas del mouse (-1 a +1)
    this.pointer.x = ((event.clientX - rect.left) / rect.width) * 2 - 1;
    this.pointer.y = -((event.clientY - rect.top) / rect.height) * 2 + 1;

    // Disparar el rayo desde la cámara
    this.raycaster.setFromCamera(this.pointer, this.camera);

    // Verificar colisiones solo con los hijos del modelo cargado (true = recursivo)
    const intersects = this.raycaster.intersectObject(this.modelGroup, true);

    if (intersects.length > 0) {
      // Tomamos el primer objeto que tocó el rayo (el más cercano a la cámara)
      const selectedMesh = intersects[0].object as THREE.Mesh;

      // Restablecer el color del objeto anterior si existía
      if (this.previousSelectedMesh && this.previousSelectedMesh !== selectedMesh) {
        const prevMaterial = this.previousSelectedMesh.material as THREE.MeshStandardMaterial;
        if (prevMaterial && prevMaterial.emissive) {
          prevMaterial.emissive.setHex(0x000000); // Apagar brillo
        }
      }

      // Darle un brillo (emissive) verde al objeto actual
      const currentMaterial = selectedMesh.material as THREE.MeshStandardMaterial;
      if (currentMaterial && currentMaterial.emissive) {
        currentMaterial.emissive.setHex(0x00ff00); // Brillo verde brillante
        currentMaterial.emissiveIntensity = 0.5;
      }

      this.previousSelectedMesh = selectedMesh;

      // --- 4. Sincronizar con el estado de Angular ---
      this.ngZone.run(() => {
        // En una app real, aquí extraerías el ID del departamento (ej. selectedMesh.userData['unitId'])
        const meshName = selectedMesh.name || 'Parte sin nombre';
        this.selectedObjectName = meshName;
        console.log('Objeto 3D intersectado:', selectedMesh);

        // Simular actualización del servicio (asumiendo que tiene ID 1)
        this.threeState.selectUnit(1);
      });

    } else {
      // Clic al vacío: limpiar selección
      if (this.previousSelectedMesh) {
        const prevMaterial = this.previousSelectedMesh.material as THREE.MeshStandardMaterial;
        if (prevMaterial && prevMaterial.emissive) prevMaterial.emissive.setHex(0x000000);
        this.previousSelectedMesh = null;
      }
      this.ngZone.run(() => {
        this.selectedObjectName = null;
        this.threeState.selectUnit(null);
      });
    }
  }

  private animate(): void {
    this.animationFrameId = requestAnimationFrame(() => this.animate());
    this.controls.update();
    this.renderer.render(this.scene, this.camera);
  }

  private onWindowResize(): void {
    const container = this.rendererContainer().nativeElement;
    this.camera.aspect = container.clientWidth / container.clientHeight;
    this.camera.updateProjectionMatrix();
    this.renderer.setSize(container.clientWidth, container.clientHeight);
  }




}