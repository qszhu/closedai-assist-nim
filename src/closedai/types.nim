import std/[
  enumutils,
  json,
  sequtils,
  tables,
]



proc toStringTable*(jso: JsonNode): Table[string, string] =
  if jso == nil: return
  for k, v in jso.pairs:
    if v.kind != JString:
      result[k] = $v
    else:
      result[k] = v.getStr



type
  FromJson[T] = proc (jso: JsonNode): T

# List

type
  CAList*[T] = object
    `object`*: string
    data*: seq[T]
    first_id*: string
    last_id*: string
    has_more*: bool

proc initList*[T](jso: JsonNode, fromJson: FromJson[T]): CAList[T] =
  doAssert jso["object"].getStr == "list"
  CAList[T](
    `object`: jso["object"].getStr,
    data: jso["data"].getElems.mapIt(it.fromJson),
    first_id: jso{"first_id"}.getStr,
    last_id: jso{"last_id"}.getStr,
    has_more: jso{"has_more"}.getBool,
  )

# Model

type
  CAModel* = object
    `object`*: string
    id*: string
    created*: int64
    owned_by*: string

proc initModel*(jso: JsonNode): CAModel =
  doAssert jso["object"].getStr == "model"
  CAModel(
    `object`: jso["object"].getStr,
    id: jso["id"].getStr,
    created: jso["created"].getBiggestInt,
    owned_by: jso["owned_by"].getStr,
  )

# Assistant Tool

type
  CAToolKind = enum
    tkCodeInterpreter = "code_interpreter"
    tkRetrieval = "retrieval"
    tkFunction = "function"

  CATool = object
    case kind*: CAToolKind
    of tkFunction:
      description*: string
      name*: string
      parameters*: JsonNode
    else:
      discard

proc initTool(jso: JsonNode): CATool =
  let kind = jso["type"].getStr
  case kind:
  of $tkCodeInterpreter:
    CATool(kind: tkCodeInterpreter)
  of $tkRetrieval:
    CATool(kind: tkRetrieval)
  of $tkFunction:
    CATool(kind: tkFunction,
      description: jso["description"].getStr,
      name: jso["name"].getStr,
      parameters: jso["parameters"],
    )
  else:
    raise newException(ValueError, "Unknown tool type: " & kind)

proc toJson*(self: CATool): JsonNode =
  result = %*{ "type": $self.kind }
  case self.kind:
  of tkFunction:
    result["description"] = %*self.description
    result["name"] = %*self.name
    result["parameters"] = %*self.parameters
  else:
    discard

# Assistant

type
  CAAssistant* = object
    `object`*: string
    id*: string
    created_at*: int64
    name*: string
    description*: string
    model*: string
    instructions*: string
    tools*: seq[CATool]
    file_ids*: seq[string]
    metadata*: Table[string, string]

proc initAssistant*(jso: JsonNode): CAAssistant =
  doAssert jso["object"].getStr == "assistant"
  CAAssistant(
    `object`: jso["object"].getStr,
    id: jso["id"].getStr,
    created_at: jso["created_at"].getBiggestInt,
    name: jso["name"].getStr,
    description: jso["description"].getStr,
    model: jso["model"].getStr,
    instructions: jso["instructions"].getStr,
    tools: jso["tools"].getElems.mapIt(it.initTool),
    file_ids: jso["file_ids"].getElems.mapIt(it.getStr),
    metadata: jso["metadata"].toStringTable,
  )

# Thread

type
  CAThread* = object
    `object`*: string
    id*: string
    created_at*: int64
    metadata*: Table[string, string]

proc initThread*(jso: JsonNode): CAThread =
  doAssert jso["object"].getStr == "thread"
  CAThread(
    `object`: jso["object"].getStr,
    id: jso["id"].getStr,
    created_at: jso["created_at"].getBiggestInt,
    metadata: jso["metadata"].toStringTable,
  )

# Message

type
  CAMessage* = object
    `object`*: string
    id*: string
    created_at*: int64
    thread_id*: string
    role*: string
    content*: seq[JsonNode] # TODO
    assistant_id*: string
    run_id*: string
    file_ids*: seq[string]
    metadata*: Table[string, string]

proc initMessage*(jso: JsonNode): CAMessage =
  doAssert jso["object"].getStr == "thread.message"
  CAMessage(
    `object`: jso["object"].getStr,
    id: jso["id"].getStr,
    created_at: jso["created_at"].getBiggestInt,
    thread_id: jso["thread_id"].getStr,
    role: jso["role"].getStr,
    content: jso["content"].getElems,
    assistant_id: jso{"assistant_id"}.getStr,
    run_id: jso{"run_id"}.getStr,
    file_ids: jso["file_ids"].getElems.mapIt(it.getStr),
    metadata: jso["metadata"].toStringTable,
  )

# Run

type
  CARunStatus* {.pure.} = enum
    queued
    in_progress
    requires_action
    cancelling
    cancelled
    failed
    completed
    expired

type
  CARun* = object
    `object`*: string
    id*: string
    created_at*: int64
    thread_id*: string
    assistant_id*: string
    status*: CARunStatus
    required_action*: JsonNode # TODO
    last_error*: JsonNode # TODO
    expires_at*: int64
    started_at*: int64
    cancelled_at*: int64
    failed_at*: int64
    completed_at*: int64
    model*: string
    instructions*: string
    tools*: seq[CATool]
    file_ids*: seq[string]
    metadata*: Table[string, string]
    usage*: JsonNode # TODO

proc initRun*(jso: JsonNode): CARun =
  doAssert jso["object"].getStr == "thread.run"
  CARun(
    `object`: jso["object"].getStr,
    id: jso["id"].getStr,
    created_at: jso["created_at"].getBiggestInt,
    thread_id: jso["thread_id"].getStr,
    assistant_id: jso["assistant_id"].getStr,
    status: CARunStatus.toSeq.filterIt(it.symbolName == jso["status"].getStr)[0],
    required_action: jso["required_action"],
    last_error: jso["last_error"],
    expires_at: jso["expires_at"].getBiggestInt,
    started_at: jso["started_at"].getBiggestInt,
    cancelled_at: jso["cancelled_at"].getBiggestInt,
    failed_at: jso["failed_at"].getBiggestInt,
    completed_at: jso["completed_at"].getBiggestInt,
    model: jso["model"].getStr,
    instructions: jso["instructions"].getStr,
    tools: jso["tools"].getElems.mapIt(it.initTool),
    file_ids: jso["file_ids"].getElems.mapIt(it.getStr),
    metadata: jso["metadata"].toStringTable,
    usage: jso["usage"],
  )

# Run step

type
  CARunStepType {.pure.} = enum
    message_creation
    tool_calls

  CARunStepStatus {.pure.} = enum
    in_progress
    cancelled
    failed
    completed
    expired

type
  CARunStep* = object
    `object`*: string
    id*: string
    created_at*: int64
    assistant_id*: string
    thread_id*: string
    run_id*: string
    `type`*: CARunStepType
    status*: CARunStepStatus
    step_details*: JsonNode # TODO
    last_error*: JsonNode # TODO
    expires_at*: int64
    cancelled_at*: int64
    failed_at*: int64
    completed_at*: int64
    metadata*: Table[string, string]
    usage*: JsonNode # TODO

proc initRunStep*(jso: JsonNode): CARunStep =
  doAssert jso["object"].getStr == "thread.run.step"
  CARunStep(
    `object`: jso["object"].getStr,
    id: jso["id"].getStr,
    created_at: jso["created_at"].getBiggestInt,
    assistant_id: jso["assistant_id"].getStr,
    thread_id: jso["thread_id"].getStr,
    run_id: jso["run_id"].getStr,
    `type`: CARunStepType.toSeq.filterIt(it.symbolName == jso["type"].getStr)[0],
    status: CARunStepStatus.toSeq.filterIt(it.symbolName == jso["status"].getStr)[0],
    step_details: jso["step_details"],
    last_error: jso["last_error"],
    expires_at: jso["expires_at"].getBiggestInt,
    cancelled_at: jso["cancelled_at"].getBiggestInt,
    failed_at: jso["failed_at"].getBiggestInt,
    completed_at: jso["completed_at"].getBiggestInt,
    metadata: jso{"metadata"}.toStringTable,
    usage: jso["usage"],
  )
