# -*- coding: utf-8 -*-
"""S01 flow_state 生成器：按当前转移机械生成状态包 JSON。"""
import json, io, os, sys

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
STATE_DIR = os.path.join(ROOT, 'state')

REQUIREMENTS = {
    "quality_bar": [],
    "project_constraints": {"aspect_ratio": "9:16", "model": "seedance-2.0", "visual_style_lock": "LIVE_ACTION_REALISM"},
    "focus": []
}

def manifest():
    return {
        "project_id": "PRJ-001", "manifest_version": "V1", "status": "ACTIVE",
        "episode_ids": ["E01"],
        "required_scene_ids": ["SCENE-E01-S01", "SCENE-E01-S02"],
        "visual_style_lock": "LIVE_ACTION_REALISM",
        "source_materials": [
            {"source_id": "SCRIPT-E01", "source_type": "SCRIPT", "version": "V1", "status": "CURRENT",
             "locator": "projects/PRJ-001/source/script.txt"}
        ],
        "constraints": {"storyboard_image_track": "DISABLED"}
    }

def decisions():
    return [
        {"decision_id": "DEC-001", "status": "CONFIRMED", "source_id": "USER-BRIEF", "scope": "PRJ-001",
         "summary": "视觉风格锁 LIVE_ACTION_REALISM：成品须像真人实拍，看不出 AI。"},
        {"decision_id": "DEC-002", "status": "CONFIRMED", "source_id": "USER-BRIEF", "scope": "E01",
         "summary": "本轮 DIRECT_TRACK（storyboard_image_track=DISABLED）：不出分镜图，剧情/分镜表通过后直出段级视频提示词。"},
        {"decision_id": "DEC-003", "status": "CONFIRMED", "source_id": "USER-BRIEF", "scope": "PRJ-001",
         "summary": "机型 seedance-2.0，竖屏 9:16，段时长 15 秒。"}
    ]

def artifact(atype, aid, ver, status, auth_id, scene_id=None, shot_id=None,
             source_beat_ids=None, source_full_ids=None, resource=None,
             segment_id=None, covered_shot_ids=None, current=True, stale=False):
    a = {
        "project_id": "PRJ-001", "artifact_type": atype, "artifact_id": aid,
        "artifact_version": ver, "full_id": aid + "-" + ver,
        "flow_authorization_id": auth_id, "status": status, "current": current,
        "stale": stale or (status == "STALE"), "scene_id": scene_id, "shot_id": shot_id,
        "source_beat_ids": source_beat_ids or [], "source_full_ids": source_full_ids or [],
        "resource": resource or ("outputs/" + aid.lower() + ".json")
    }
    if segment_id is not None:
        a["segment_id"] = segment_id
    if covered_shot_ids is not None:
        a["covered_shot_ids"] = covered_shot_ids
    return a

def authorization(auth_id, stage, action, target, status, scope, requirements,
                  artifact_full_id=None, ticket_id=None, issued_at="2026-08-17T16:00:00+08:00"):
    return {
        "authorization_id": auth_id, "project_id": "PRJ-001", "stage": stage,
        "action": action, "target": target, "status": status, "scope": scope,
        "requirements": requirements, "artifact_full_id": artifact_full_id,
        "ticket_id": ticket_id, "issued_at": issued_at
    }

def scope(episode_ids=None, scene_ids=None, shot_ids=None, beat_ids=None):
    return {"episode_ids": episode_ids or ["E01"], "scene_ids": scene_ids or [],
            "shot_ids": shot_ids or [], "beat_ids": beat_ids or []}

def write_state(name, stage, state, action, target, artifacts, authorizations,
                qa_mode=None, artifact_full_id=None, ticket_id=None, auth_id=None,
                dsp_scope=None, requirements=None, next_action=None, reason="",
                last_qa_verdict=None, run_log=None, delivery=None):
    req = requirements or REQUIREMENTS
    bundle = {
        "schema_version": "1.0",
        "project_manifest": manifest(),
        "stage_state": {
            "project_id": "PRJ-001", "current_stage": stage, "state": state,
            "current_artifact_full_id": artifact_full_id, "last_qa_verdict": last_qa_verdict,
            "blocking_reasons": [], "next_action": next_action or action
        },
        "decision_ledger": decisions(),
        "artifact_index": artifacts,
        "flow_authorizations": authorizations,
        "pending_repair_tickets": [],
        "run_log": run_log or [],
        "dispatch": {
            "action": action, "target": target, "qa_mode": qa_mode,
            "artifact_full_id": artifact_full_id, "ticket_id": ticket_id,
            "authorization_id": auth_id, "scope": dsp_scope or scope(),
            "requirements": req, "reason": reason
        },
        "delivery": delivery or []
    }
    path = os.path.join(STATE_DIR, name + ".json")
    with io.open(path, "w", encoding="utf-8", newline="\n") as f:
        json.dump(bundle, f, ensure_ascii=False, indent=2)
    # 同时刷新 current.json 供校验器与 QA 信封使用
    with io.open(os.path.join(STATE_DIR, "current.json"), "w", encoding="utf-8", newline="\n") as f:
        json.dump(bundle, f, ensure_ascii=False, indent=2)
    print(path)

if __name__ == "__main__":
    pass
