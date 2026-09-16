import assert from "node:assert/strict";
import test from "node:test";

import { inspect3dScene } from "../src/sceneDiagnostics.js";
import type { ToolEnvelope } from "../src/types.js";

test("inspect3dScene summarizes healthy 3D scene hints", () => {
  const result = inspect3dScene(snapshotEnvelope({
    scene_tree: {
      root: {
        path: "/root/Main",
        name: "Main",
        type: "Node3D",
        three_d: { visible: true },
        children: [
          {
            path: "/root/Main/Camera3D",
            name: "Camera3D",
            type: "Camera3D",
            three_d: {
              visible: true,
              camera: { current: true, projection: "perspective", fov_degrees: 70, near: 0.05, far: 4000 },
            },
            children: [],
          },
          {
            path: "/root/Main/KeyLight",
            name: "KeyLight",
            type: "DirectionalLight3D",
            three_d: { visible: true, light: { energy: 1, shadows_enabled: true } },
            children: [],
          },
          {
            path: "/root/Main/Mesh",
            name: "Mesh",
            type: "MeshInstance3D",
            three_d: { visible: true, mesh: { surface_count: 1, material_count: 1 } },
            children: [],
          },
          {
            path: "/root/Main/Collider",
            name: "Collider",
            type: "CollisionShape3D",
            three_d: { visible: true, collision_shape: { shape_type: "BoxShape3D", disabled: false } },
            children: [],
          },
          {
            path: "/root/Main/NavRegion",
            name: "NavRegion",
            type: "NavigationRegion3D",
            three_d: { visible: true, navigation_region: { enabled: true, navigation_mesh_path: "res://nav.tres" } },
            children: [],
          },
        ],
      },
      node_count: 6,
      truncated: false,
    },
  }));

  assert.equal(result.status, "ok");
  assert.equal((result.summary as { camera_count: number }).camera_count, 1);
  assert.equal((result.summary as { light_count: number }).light_count, 1);
  assert.equal((result.summary as { collision_shape_count: number }).collision_shape_count, 1);
  assert.equal((result.summary as { navigation_region_count: number }).navigation_region_count, 1);
  assert.deepEqual((result.findings as Array<{ severity: string }>).filter((finding) => finding.severity === "warning"), []);
});

test("inspect3dScene reports safe suggestions for common 3D issues", () => {
  const result = inspect3dScene(snapshotEnvelope({
    scene_tree: {
      root: {
        path: "/root/Main",
        name: "Main",
        type: "Node3D",
        three_d: { visible: true },
        children: [
          {
            path: "/root/Main/Mesh",
            name: "Mesh",
            type: "MeshInstance3D",
            three_d: { visible: true, mesh: { surface_count: 0, material_count: 0 } },
            children: [],
          },
        ],
      },
      node_count: 2,
      truncated: false,
    },
  }));

  const findings = result.findings as Array<{ code: string; severity: string }>;
  assert.equal(result.status, "ok");
  assert.ok(findings.some((finding) => finding.code === "camera_missing"));
  assert.ok(findings.some((finding) => finding.code === "light_missing"));
  assert.ok(findings.some((finding) => finding.code === "mesh_without_collision_shapes"));
  assert.ok((result.safe_suggestions as Array<{ mutation_required: boolean }>).every((suggestion) => suggestion.mutation_required === false));
});

test("inspect3dScene estimates camera framing and debug layers", () => {
  const result = inspect3dScene(snapshotEnvelope({
    scene_tree: {
      root: {
        path: "/root/Main",
        name: "Main",
        type: "Node3D",
        three_d: { visible: true },
        children: [
          {
            path: "/root/Main/Camera3D",
            name: "Camera3D",
            type: "Camera3D",
            three_d: {
              transform: { position: { x: 0, y: 0, z: 0 }, scale: { x: 1, y: 1, z: 1 } },
              visible: true,
              camera: { current: true, projection: "perspective", fov_degrees: 70, near: 0.05, far: 1 },
            },
            children: [],
          },
          {
            path: "/root/Main/HugeMesh",
            name: "HugeMesh",
            type: "MeshInstance3D",
            three_d: {
              transform: { position: { x: 0, y: 0, z: 20 }, scale: { x: 10, y: 10, z: 10 } },
              visible: true,
              mesh: {
                surface_count: 2,
                material_count: 1,
                aabb: { position: { x: -0.5, y: -0.5, z: -0.5 }, size: { x: 1, y: 1, z: 1 } },
              },
            },
            children: [],
          },
          {
            path: "/root/Main/Collider",
            name: "Collider",
            type: "CollisionShape3D",
            three_d: { visible: true, collision_shape: { shape_type: "BoxShape3D", disabled: true } },
            children: [],
          },
        ],
      },
      node_count: 4,
      truncated: false,
    },
  }));

  const findings = result.findings as Array<{ code: string }>;
  assert.ok(findings.some((finding) => finding.code === "camera_far_clip_may_miss_scene"));
  assert.ok(findings.some((finding) => finding.code === "mesh_material_count_below_surface_count"));
  assert.equal((result.debug_layers as { collision_shapes: unknown[] }).collision_shapes.length, 1);
  assert.equal((result.camera_framing as { status: string }).status, "ok");
});

test("inspect3dScene reports runtime performance monitor values when present", () => {
  const result = inspect3dScene(snapshotEnvelope({
    performance: {
      captured_at: "2026-06-13T00:00:00.000Z",
      source: "godot_performance_monitor",
      status: "available",
      sample_interval_seconds: 1,
      monitors: {
        render_total_draw_calls_in_frame: 2501,
        render_total_objects_in_frame: 400,
        render_total_primitives_in_frame: 90000,
        physics_3d_active_objects: 42,
        physics_3d_collision_pairs: 1200,
        physics_3d_island_count: 7,
        navigation_active_maps: 1,
        navigation_region_count: 2,
        navigation_agent_count: 3,
      },
      samples: [
        {
          captured_at: "2026-06-13T00:00:00.000Z",
          monitors: {
            render_total_draw_calls_in_frame: 100,
            render_total_primitives_in_frame: 1000,
            render_total_objects_in_frame: 10,
            physics_3d_active_objects: 4,
            physics_3d_collision_pairs: 20,
            navigation_agent_count: 1,
          },
        },
        {
          captured_at: "2026-06-13T00:00:01.000Z",
          monitors: {
            render_total_draw_calls_in_frame: 2501,
            render_total_primitives_in_frame: 90000,
            render_total_objects_in_frame: 400,
            physics_3d_active_objects: 42,
            physics_3d_collision_pairs: 1200,
            navigation_agent_count: 3,
          },
        },
      ],
    },
    scene_tree: {
      root: {
        path: "/root/Main",
        name: "Main",
        type: "Node3D",
        three_d: { visible: true },
        children: [],
      },
      node_count: 1,
      truncated: false,
    },
  }));

  const probes = result.performance_probes as {
    draw_calls: { status: string; value: number };
    physics_cost: { status: string; collision_pairs: number };
    navigation: { status: string; agent_count: number };
    timeline: {
      status: string;
      sample_count: number;
      draw_calls: { max: number; average: number };
      physics_collision_pairs: { max: number };
    };
  };
  const findings = result.findings as Array<{ code: string }>;
  assert.equal(probes.draw_calls.status, "available");
  assert.equal(probes.draw_calls.value, 2501);
  assert.equal(probes.physics_cost.collision_pairs, 1200);
  assert.equal(probes.navigation.agent_count, 3);
  assert.equal(probes.timeline.status, "available");
  assert.equal(probes.timeline.sample_count, 2);
  assert.equal(probes.timeline.draw_calls.max, 2501);
  assert.equal(probes.timeline.draw_calls.average, 1300.5);
  assert.equal(probes.timeline.physics_collision_pairs.max, 1200);
  assert.ok(findings.some((finding) => finding.code === "draw_calls_high"));
  assert.ok(findings.some((finding) => finding.code === "physics_collision_pairs_moderate"));
});

function snapshotEnvelope(snapshot: Record<string, unknown>): ToolEnvelope {
  return {
    status: "ok",
    snapshot: {
      protocol_version: "godot-codex-bridge/0.1",
      generated_at: "2026-06-13T00:00:00.000Z",
      current_scene: { path: "res://scenes/main.tscn" },
      ...snapshot,
    },
  };
}
