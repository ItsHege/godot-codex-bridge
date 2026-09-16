import type { JsonObject, JsonValue, ToolEnvelope } from "./types.js";

export function inspect3dScene(snapshotEnvelope: ToolEnvelope): ToolEnvelope {
  if (snapshotEnvelope.status !== "ok") {
    return snapshotEnvelope;
  }

  const snapshot = objectOrNull(snapshotEnvelope.snapshot);
  if (!snapshot) {
    return {
      status: "error",
      error: {
        code: "invalid_snapshot",
        message: "Cannot inspect 3D scene because snapshot payload is invalid.",
      },
    };
  }

  const sceneTree = objectOrNull(snapshot.scene_tree);
  const root = objectOrNull(sceneTree?.root);
  if (!root) {
    return {
      status: "not_found",
      error: {
        code: "scene_tree_missing",
        message: "Cannot inspect 3D scene because snapshot.scene_tree.root is missing.",
      },
    };
  }

  const nodes = flattenNodes(root);
  const selectedNodes = arrayOrEmpty(snapshot.selected_nodes)
    .map((entry) => objectOrNull(entry))
    .map((entry) => objectOrNull(entry?.node))
    .filter((node): node is JsonObject => node !== null);
  const findings: JsonObject[] = [];
  const counts = makeCounts(nodes);
  const sceneBounds = estimateSceneBounds(counts.meshes);

  inspectCameras(counts.cameras, findings);
  const cameraFraming = inspectCameraFraming(counts.cameras, sceneBounds, findings);
  inspectLights(counts.lights, findings);
  inspectMeshesAndCollisions(counts.meshes, counts.collisionShapes, findings);
  inspectNavigation(counts.navigationRegions, findings);
  inspectVisibility(nodes, findings);
  inspectSceneSize(sceneTree, counts.totalNodes, findings);
  const performanceProbes = inspectPerformance(snapshot, sceneTree, counts.totalNodes, findings);

  return {
    status: "ok",
    diagnostics_version: "godot-codex-bridge/3d-diagnostics-v1",
    protocol_version: stringOrNull(snapshot.protocol_version),
    generated_at: stringOrNull(snapshot.generated_at),
    current_scene: objectOrNull(snapshot.current_scene),
    summary: {
      node_count: numberOrDefault(sceneTree?.node_count, counts.totalNodes),
      traversed_node_count: counts.totalNodes,
      camera_count: counts.cameras.length,
      current_camera_count: counts.cameras.filter((node) => boolAt(node, ["three_d", "camera", "current"]) === true).length,
      light_count: counts.lights.length,
      mesh_count: counts.meshes.length,
      collision_shape_count: counts.collisionShapes.length,
      navigation_region_count: counts.navigationRegions.length,
      selected_node_count: selectedNodes.length,
      truncated: sceneTree?.truncated === true,
    },
    selected_nodes: selectedNodes.map((node) => summarizeNode(node)),
    camera_framing: cameraFraming,
    debug_layers: {
      collision_shapes: counts.collisionShapes.map((node) => ({
        path: node.path ?? null,
        type: node.type ?? null,
        shape_type: objectAt(node, ["three_d", "collision_shape"])?.shape_type ?? null,
        disabled: objectAt(node, ["three_d", "collision_shape"])?.disabled ?? null,
      })),
      navigation_regions: counts.navigationRegions.map((node) => ({
        path: node.path ?? null,
        type: node.type ?? null,
        enabled: objectAt(node, ["three_d", "navigation_region"])?.enabled ?? null,
        navigation_mesh_path: objectAt(node, ["three_d", "navigation_region"])?.navigation_mesh_path ?? null,
      })),
    },
    performance_probes: performanceProbes,
    findings,
    safe_suggestions: findings
      .filter((finding) => finding.severity === "warning" || finding.severity === "error")
      .map((finding) => ({
        code: finding.code,
        node_path: finding.node_path ?? null,
        suggestion: suggestionFor(finding),
        mutation_required: false,
      })),
  };
}

function inspectPerformance(snapshot: JsonObject, sceneTree: JsonObject | null, nodeCount: number, findings: JsonObject[]): JsonObject {
  const performance = objectOrNull(snapshot.performance);
  const monitors = objectOrNull(performance?.monitors);
  const drawCalls = numberOrNull(monitors?.render_total_draw_calls_in_frame);
  const primitives = numberOrNull(monitors?.render_total_primitives_in_frame);
  const renderObjects = numberOrNull(monitors?.render_total_objects_in_frame);
  const physicsObjects = numberOrNull(monitors?.physics_3d_active_objects);
  const collisionPairs = numberOrNull(monitors?.physics_3d_collision_pairs);
  const samples = arrayOrEmpty(performance?.samples)
    .map((sample) => objectOrNull(sample))
    .filter((sample): sample is JsonObject => sample !== null);

  if (drawCalls !== null && drawCalls > 2_000) {
    findings.push(finding("warning", "draw_calls_high", "Godot performance monitor reports more than 2000 draw calls in the current frame."));
  } else if (drawCalls !== null && drawCalls > 1_000) {
    findings.push(finding("info", "draw_calls_moderate", "Godot performance monitor reports more than 1000 draw calls in the current frame."));
  }

  if (collisionPairs !== null && collisionPairs > 5_000) {
    findings.push(finding("warning", "physics_collision_pairs_high", "Godot performance monitor reports more than 5000 3D collision pairs."));
  } else if (collisionPairs !== null && collisionPairs > 1_000) {
    findings.push(finding("info", "physics_collision_pairs_moderate", "Godot performance monitor reports more than 1000 3D collision pairs."));
  }

  return {
    node_count: numberOrDefault(sceneTree?.node_count, nodeCount),
    source: performance?.source ?? null,
    captured_at: performance?.captured_at ?? null,
    draw_calls: drawCalls === null
      ? {
          status: "unavailable",
          reason: "No render_total_draw_calls_in_frame monitor was present in the context snapshot.",
        }
      : {
          status: "available",
          value: drawCalls,
          render_objects: renderObjects,
          primitives,
        },
    physics_cost: physicsObjects === null && collisionPairs === null
      ? {
          status: "unavailable",
          reason: "No 3D physics performance monitors were present in the context snapshot.",
        }
      : {
          status: "available",
          active_objects: physicsObjects,
          collision_pairs: collisionPairs,
          island_count: numberOrNull(monitors?.physics_3d_island_count),
        },
    navigation: {
      status: monitors ? "available" : "unavailable",
      active_maps: numberOrNull(monitors?.navigation_active_maps),
      region_count: numberOrNull(monitors?.navigation_region_count),
      agent_count: numberOrNull(monitors?.navigation_agent_count),
    },
    timeline: summarizePerformanceTimeline(samples, performance),
  };
}

function summarizePerformanceTimeline(samples: JsonObject[], performance: JsonObject | null): JsonObject {
  if (samples.length === 0) {
    return {
      status: "unavailable",
      reason: "No performance samples were present in the context snapshot.",
      sample_count: 0,
    };
  }

  return {
    status: "available",
    sample_count: samples.length,
    sample_interval_seconds: numberOrNull(performance?.sample_interval_seconds),
    first_captured_at: stringOrNull(samples[0]?.captured_at),
    last_captured_at: stringOrNull(samples[samples.length - 1]?.captured_at),
    draw_calls: monitorStats(samples, "render_total_draw_calls_in_frame"),
    primitives: monitorStats(samples, "render_total_primitives_in_frame"),
    render_objects: monitorStats(samples, "render_total_objects_in_frame"),
    physics_active_objects: monitorStats(samples, "physics_3d_active_objects"),
    physics_collision_pairs: monitorStats(samples, "physics_3d_collision_pairs"),
    navigation_agents: monitorStats(samples, "navigation_agent_count"),
  };
}

function monitorStats(samples: JsonObject[], monitorName: string): JsonObject {
  const values = samples
    .map((sample) => numberOrNull(objectOrNull(sample.monitors)?.[monitorName]))
    .filter((value): value is number => value !== null);
  if (values.length === 0) {
    return { status: "unavailable" };
  }
  const min = Math.min(...values);
  const max = Math.max(...values);
  const average = values.reduce((total, value) => total + value, 0) / values.length;
  return {
    status: "available",
    min,
    max,
    average,
  };
}

function makeCounts(nodes: JsonObject[]): {
  totalNodes: number;
  cameras: JsonObject[];
  lights: JsonObject[];
  meshes: JsonObject[];
  collisionShapes: JsonObject[];
  navigationRegions: JsonObject[];
} {
  return {
    totalNodes: nodes.length,
    cameras: nodes.filter((node) => objectAt(node, ["three_d", "camera"]) !== null),
    lights: nodes.filter((node) => objectAt(node, ["three_d", "light"]) !== null),
    meshes: nodes.filter((node) => objectAt(node, ["three_d", "mesh"]) !== null),
    collisionShapes: nodes.filter((node) => objectAt(node, ["three_d", "collision_shape"]) !== null),
    navigationRegions: nodes.filter((node) => objectAt(node, ["three_d", "navigation_region"]) !== null),
  };
}

function inspectCameras(cameras: JsonObject[], findings: JsonObject[]): void {
  if (cameras.length === 0) {
    findings.push(finding("warning", "camera_missing", "No Camera3D node was found in the scene."));
    return;
  }

  const currentCameras = cameras.filter((node) => boolAt(node, ["three_d", "camera", "current"]) === true);
  if (currentCameras.length === 0) {
    findings.push(finding("warning", "current_camera_missing", "No Camera3D is marked current."));
  }
  if (currentCameras.length > 1) {
    findings.push(finding("warning", "multiple_current_cameras", "Multiple Camera3D nodes are marked current."));
  }

  for (const camera of cameras) {
    const cameraData = objectAt(camera, ["three_d", "camera"]);
    const near = numberOrNull(cameraData?.near);
    const far = numberOrNull(cameraData?.far);
    const fov = numberOrNull(cameraData?.fov_degrees);
    if (near !== null && near <= 0) {
      findings.push(finding("warning", "camera_near_invalid", "Camera near plane should be greater than 0.", camera));
    }
    if (near !== null && far !== null && far <= near) {
      findings.push(finding("warning", "camera_far_before_near", "Camera far plane should be greater than near plane.", camera));
    }
    if (fov !== null && (fov < 20 || fov > 120)) {
      findings.push(finding("info", "camera_fov_unusual", "Camera FOV is outside the common 20-120 degree range.", camera));
    }
  }
}

function inspectLights(lights: JsonObject[], findings: JsonObject[]): void {
  if (lights.length === 0) {
    findings.push(finding("warning", "light_missing", "No Light3D node was found in the scene."));
    return;
  }

  let totalEnergy = 0;
  for (const light of lights) {
    const lightData = objectAt(light, ["three_d", "light"]);
    const energy = numberOrNull(lightData?.energy);
    totalEnergy += energy ?? 0;
    if (energy !== null && energy <= 0) {
      findings.push(finding("warning", "light_energy_zero", "Light energy is zero or negative.", light));
    }
    if (lightData?.shadows_enabled === false) {
      findings.push(finding("info", "light_shadows_disabled", "Light shadows are disabled.", light));
    }
  }

  if (totalEnergy > 0 && totalEnergy < 0.25) {
    findings.push(finding("info", "scene_light_energy_low", "Total captured light energy is very low; confirm the scene uses environment lighting or intentional darkness."));
  }
}

function inspectMeshesAndCollisions(meshes: JsonObject[], collisionShapes: JsonObject[], findings: JsonObject[]): void {
  if (meshes.length > 0 && collisionShapes.length === 0) {
    findings.push(finding("warning", "mesh_without_collision_shapes", "Scene has MeshInstance3D nodes but no CollisionShape3D nodes."));
  }

  for (const mesh of meshes) {
    const meshData = objectAt(mesh, ["three_d", "mesh"]);
    if (numberOrDefault(meshData?.surface_count, 0) === 0) {
      findings.push(finding("warning", "mesh_surface_missing", "Mesh has no surfaces.", mesh));
    }
    if (numberOrDefault(meshData?.material_count, 0) === 0) {
      findings.push(finding("info", "mesh_material_missing", "Mesh has no material override or material count in the snapshot.", mesh));
    }
    if (
      numberOrDefault(meshData?.surface_count, 0) > 0 &&
      numberOrDefault(meshData?.material_count, 0) > 0 &&
      numberOrDefault(meshData?.material_count, 0) < numberOrDefault(meshData?.surface_count, 0)
    ) {
      findings.push(finding("info", "mesh_material_count_below_surface_count", "Mesh material count is lower than surface count; confirm all surfaces have intended materials.", mesh));
    }
  }

  for (const shape of collisionShapes) {
    const shapeData = objectAt(shape, ["three_d", "collision_shape"]);
    if (shapeData?.disabled === true) {
      findings.push(finding("warning", "collision_shape_disabled", "CollisionShape3D is disabled.", shape));
    }
    if (shapeData?.shape_type === null || shapeData?.shape_type === undefined) {
      findings.push(finding("warning", "collision_shape_missing_resource", "CollisionShape3D has no shape resource.", shape));
    }
  }
}

function inspectNavigation(navRegions: JsonObject[], findings: JsonObject[]): void {
  for (const region of navRegions) {
    const navData = objectAt(region, ["three_d", "navigation_region"]);
    if (navData?.enabled === false) {
      findings.push(finding("warning", "navigation_region_disabled", "NavigationRegion3D is disabled.", region));
    }
    if (navData?.navigation_mesh_path === null || navData?.navigation_mesh_path === undefined) {
      findings.push(finding("warning", "navigation_mesh_missing", "NavigationRegion3D has no navigation mesh.", region));
    }
  }
}

function inspectCameraFraming(cameras: JsonObject[], sceneBounds: JsonObject | null, findings: JsonObject[]): JsonObject {
  const currentCameras = cameras.filter((node) => boolAt(node, ["three_d", "camera", "current"]) === true);
  if (!sceneBounds) {
    if (currentCameras.length > 0) {
      findings.push(finding("info", "camera_framing_bounds_unavailable", "Camera framing could not be estimated because no mesh bounds were captured."));
    }
    return {
      status: "unavailable",
      reason: "No MeshInstance3D AABB data was available in the context snapshot.",
      scene_bounds: null,
      current_cameras: currentCameras.map((node) => summarizeNode(node)),
    };
  }

  const cameraResults = currentCameras.map((camera) => {
    const position = vectorAt(camera, ["three_d", "transform", "position"]);
    const far = numberOrNull(objectAt(camera, ["three_d", "camera"])?.far);
    const distance = position ? distanceBetween(position, sceneBounds.center as JsonObject) : null;
    const radius = numberOrNull(sceneBounds.radius);
    const far_margin = distance !== null && radius !== null && far !== null ? far - (distance + radius) : null;
    if (far_margin !== null && far_margin < 0) {
      findings.push(finding("warning", "camera_far_clip_may_miss_scene", "Current camera far plane may not include all captured mesh bounds.", camera));
    }
    if (distance !== null && radius !== null && radius > 0 && distance < radius * 0.25) {
      findings.push(finding("info", "camera_inside_scene_bounds", "Current camera appears very close to the estimated scene bounds center.", camera));
    }
    return {
      camera: summarizeNode(camera),
      distance_to_scene_center: distance,
      estimated_scene_radius: radius,
      far_clip_margin: far_margin,
      status: far_margin !== null && far_margin < 0 ? "warning" : "ok",
    };
  });

  return {
    status: currentCameras.length === 0 ? "unavailable" : "ok",
    scene_bounds: sceneBounds,
    current_cameras: cameraResults,
  };
}

function inspectVisibility(nodes: JsonObject[], findings: JsonObject[]): void {
  for (const node of nodes) {
    const threeD = objectOrNull(node.three_d);
    if (threeD && threeD.visible === false && hasDiagnosticRole(threeD)) {
      findings.push(finding("info", "important_3d_node_hidden", "Important 3D node is hidden.", node));
    }
  }
}

function inspectSceneSize(sceneTree: JsonObject | null, nodeCount: number, findings: JsonObject[]): void {
  if (sceneTree?.truncated === true) {
    findings.push(finding("warning", "scene_tree_truncated", "Scene tree snapshot was truncated; diagnostics may be incomplete."));
  }
  if (nodeCount > 1_000) {
    findings.push(finding("warning", "node_count_high", "Scene has more than 1000 traversed nodes; inspect performance hotspots."));
  } else if (nodeCount > 500) {
    findings.push(finding("info", "node_count_moderate", "Scene has more than 500 traversed nodes."));
  }
}

function flattenNodes(root: JsonObject): JsonObject[] {
  const nodes: JsonObject[] = [];
  const stack: JsonObject[] = [root];
  while (stack.length > 0) {
    const node = stack.pop();
    if (!node) {
      continue;
    }
    nodes.push(node);
    for (const child of arrayOrEmpty(node.children).reverse()) {
      const childObject = objectOrNull(child);
      if (childObject) {
        stack.push(childObject);
      }
    }
  }
  return nodes;
}

function estimateSceneBounds(meshes: JsonObject[]): JsonObject | null {
  let minX = Number.POSITIVE_INFINITY;
  let minY = Number.POSITIVE_INFINITY;
  let minZ = Number.POSITIVE_INFINITY;
  let maxX = Number.NEGATIVE_INFINITY;
  let maxY = Number.NEGATIVE_INFINITY;
  let maxZ = Number.NEGATIVE_INFINITY;
  let found = false;

  for (const mesh of meshes) {
    const aabb = objectAt(mesh, ["three_d", "mesh", "aabb"]);
    const aabbPosition = vectorAtObject(aabb, "position");
    const aabbSize = vectorAtObject(aabb, "size");
    const position = vectorAt(mesh, ["three_d", "transform", "position"]) ?? { x: 0, y: 0, z: 0 };
    const scale = vectorAt(mesh, ["three_d", "transform", "scale"]) ?? { x: 1, y: 1, z: 1 };
    if (!aabbPosition || !aabbSize) {
      continue;
    }

    const localMin = {
      x: position.x + aabbPosition.x * scale.x,
      y: position.y + aabbPosition.y * scale.y,
      z: position.z + aabbPosition.z * scale.z,
    };
    const localMax = {
      x: localMin.x + aabbSize.x * Math.abs(scale.x),
      y: localMin.y + aabbSize.y * Math.abs(scale.y),
      z: localMin.z + aabbSize.z * Math.abs(scale.z),
    };
    minX = Math.min(minX, localMin.x, localMax.x);
    minY = Math.min(minY, localMin.y, localMax.y);
    minZ = Math.min(minZ, localMin.z, localMax.z);
    maxX = Math.max(maxX, localMin.x, localMax.x);
    maxY = Math.max(maxY, localMin.y, localMax.y);
    maxZ = Math.max(maxZ, localMin.z, localMax.z);
    found = true;
  }

  if (!found) {
    return null;
  }

  const center = {
    x: (minX + maxX) / 2,
    y: (minY + maxY) / 2,
    z: (minZ + maxZ) / 2,
  };
  const size = {
    x: maxX - minX,
    y: maxY - minY,
    z: maxZ - minZ,
  };
  return {
    min: { x: minX, y: minY, z: minZ },
    max: { x: maxX, y: maxY, z: maxZ },
    center,
    size,
    radius: Math.sqrt(size.x ** 2 + size.y ** 2 + size.z ** 2) / 2,
  };
}

function finding(severity: string, code: string, message: string, node?: JsonObject): JsonObject {
  return {
    severity,
    code,
    message,
    node_path: typeof node?.path === "string" ? node.path : null,
    node_type: typeof node?.type === "string" ? node.type : null,
  };
}

function summarizeNode(node: JsonObject): JsonObject {
  return {
    path: typeof node.path === "string" ? node.path : null,
    name: typeof node.name === "string" ? node.name : null,
    type: typeof node.type === "string" ? node.type : null,
    has_camera: objectAt(node, ["three_d", "camera"]) !== null,
    has_light: objectAt(node, ["three_d", "light"]) !== null,
    has_mesh: objectAt(node, ["three_d", "mesh"]) !== null,
    has_collision_shape: objectAt(node, ["three_d", "collision_shape"]) !== null,
    has_navigation_region: objectAt(node, ["three_d", "navigation_region"]) !== null,
  };
}

function suggestionFor(finding: JsonObject): string {
  switch (finding.code) {
    case "camera_missing":
      return "Add or select a Camera3D before validating framing.";
    case "current_camera_missing":
      return "Mark the intended gameplay Camera3D as current.";
    case "multiple_current_cameras":
      return "Keep one intended current Camera3D for the active scene.";
    case "light_missing":
      return "Add at least one Light3D or confirm the scene relies on environment lighting.";
    case "mesh_without_collision_shapes":
      return "Add CollisionShape3D/CollisionObject3D coverage for meshes that need physics interaction.";
    case "navigation_mesh_missing":
      return "Assign or bake a NavigationMesh for this NavigationRegion3D.";
    case "camera_far_clip_may_miss_scene":
      return "Increase the current camera far plane or move/framing-adjust the camera after reviewing the scene bounds.";
    case "collision_shape_disabled":
      return "Enable the collision shape if this object should participate in physics.";
    default:
      return "Review this diagnostic in Godot before making changes.";
  }
}

function hasDiagnosticRole(threeD: JsonObject): boolean {
  return Boolean(
    threeD.camera ||
      threeD.light ||
      threeD.mesh ||
      threeD.collision_shape ||
      threeD.navigation_region,
  );
}

function objectAt(value: JsonObject, path: string[]): JsonObject | null {
  let current: JsonValue | undefined = value;
  for (const key of path) {
    const object = objectOrNull(current);
    if (!object) {
      return null;
    }
    current = object[key];
  }
  return objectOrNull(current);
}

function boolAt(value: JsonObject, path: string[]): boolean | null {
  let current: JsonValue | undefined = value;
  for (const key of path) {
    const object = objectOrNull(current);
    if (!object) {
      return null;
    }
    current = object[key];
  }
  return typeof current === "boolean" ? current : null;
}

function vectorAt(value: JsonObject, path: string[]): { x: number; y: number; z: number } | null {
  const object = objectAt(value, path);
  return vectorFromObject(object);
}

function vectorAtObject(value: JsonObject | null, key: string): { x: number; y: number; z: number } | null {
  return value ? vectorFromObject(objectOrNull(value[key])) : null;
}

function vectorFromObject(value: JsonObject | null): { x: number; y: number; z: number } | null {
  const x = numberOrNull(value?.x);
  const y = numberOrNull(value?.y);
  const z = numberOrNull(value?.z);
  return x === null || y === null || z === null ? null : { x, y, z };
}

function distanceBetween(a: { x: number; y: number; z: number }, b: JsonObject): number | null {
  const bx = numberOrNull(b.x);
  const by = numberOrNull(b.y);
  const bz = numberOrNull(b.z);
  if (bx === null || by === null || bz === null) {
    return null;
  }
  return Math.sqrt((a.x - bx) ** 2 + (a.y - by) ** 2 + (a.z - bz) ** 2);
}

function objectOrNull(value: JsonValue | undefined): JsonObject | null {
  return typeof value === "object" && value !== null && !Array.isArray(value) ? value : null;
}

function arrayOrEmpty(value: JsonValue | undefined): JsonValue[] {
  return Array.isArray(value) ? value : [];
}

function stringOrNull(value: JsonValue | undefined): string | null {
  return typeof value === "string" ? value : null;
}

function numberOrNull(value: JsonValue | undefined): number | null {
  return typeof value === "number" && Number.isFinite(value) ? value : null;
}

function numberOrDefault(value: JsonValue | undefined, fallback: number): number {
  return typeof value === "number" && Number.isFinite(value) ? value : fallback;
}
