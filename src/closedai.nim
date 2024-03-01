import std/[
  asyncdispatch,
  httpclient,
  json,
  sequtils,
  strformat,
  tables,
  uri,
]

import closedai/types

export types, asyncdispatch, httpclient, json



const HOST = "https://api.openai.com/v1".parseUri

type
  ClosedAi* = ref object
    apiKey, organization, user: string
    proxy: Proxy

proc newClosedAi*(apiKey: string, organization = "", user = "", proxy: Proxy = nil): ClosedAi =
  result.new
  result.apiKey = apiKey
  result.organization = organization
  result.user = user
  result.proxy = proxy

proc newClient(self: ClosedAi): AsyncHttpClient =
  result = newAsyncHttpClient(proxy = self.proxy)
  result.headers = newHttpHeaders({
    "Content-Type": "application/json",
    "Authorization": &"Bearer {self.apiKey}",
  })
  if self.organization.len > 0:
    result.headers["OpenAI-Organization"] = self.organization

proc request(client: AsyncHttpClient, url: Uri,
  params: JsonNode = %*{}, httpMethod = HttpGet,
): Future[JsonNode] {.async.} =
  var url = url
  var body = ""

  if httpMethod == HttpGet or httpMethod == HttpDelete:
    url = url ? params.toStringTable.pairs.toSeq
  elif httpMethod == HttpPost or httpMethod == HttpPut:
    body = $params

  let
    resp = await client.request(
      url = url,
      httpMethod = httpMethod,
      body = body
    )
    respBody = await resp.body
  let jso = respBody.parseJson
  if "error" in jso:
    raise newException(CatchableError, jso["error"]["message"].getStr)
  return jso

type
  CAListOptions* = object
    limit*: int
    order*: string
    after*: string
    before*: string

proc initListOptions*(limit = 20, order = "desc", after = "", before = ""): CAListOptions =
  CAListOptions(
    limit: limit,
    order: order,
    after: after,
    before: before,
  )

proc toJson(self: CAListOptions): JsonNode =
  result = %*{ "limit": self.limit, "order": self.order }
  if self.after.len > 0:
    result["after"] = %*self.after
  if self.before.len > 0:
    result["before"] = %*self.before

# Models

proc listModels*(self: ClosedAi): Future[CAList[CAModel]] {.async.} =
  var client = self.newClient
  let url = HOST / "models"
  let res = await client.request(url)
  return initList[CAModel](res, initModel)

# Assistants

proc newAssistantClient(self: ClosedAi): AsyncHttpClient =
  result = self.newClient
  result.headers["OpenAI-Beta"] = "assistants=v1"

proc createAssistant*(self: ClosedAi, e: CAAssistant): Future[CAAssistant] {.async.} =
  var client = self.newAssistantClient

  let uri = HOST / "assistants"

  var params = %*{ "model": e.model }
  if e.name.len > 0:
    params["name"] = %*(e.name)
  if e.description.len > 0:
    params["description"] = %*(e.description)
  if e.instructions.len > 0:
    params["instructions"] = %*(e.instructions)
  if e.tools.len > 0:
    params["tools"] = %*(e.tools.mapIt(it.toJson))
  if e.file_ids.len > 0:
    params["file_ids"] = %*(e.file_ids)
  if e.metadata.len > 0:
    params["metadata"] = %*(e.metadata)

  let res = await client.request(uri, params, HttpPost)
  return res.initAssistant

proc listAssistants*(self: ClosedAi, opts = initListOptions()): Future[CAList[CAAssistant]] {.async.} =
  var client = self.newAssistantClient
  let uri = HOST / "assistants"
  let params = opts.toJson
  let resp = await client.request(uri, params)
  return initList[CAAssistant](resp, initAssistant)

# Thread

proc createThread*(self: ClosedAi): Future[CAThread] {.async.} =
  var client = self.newAssistantClient

  let uri = HOST / "threads"

  var params = %*{} # TODO

  let res = await client.request(uri, params, HttpPost)
  return res.initThread

# Message

proc createMessage*(self: ClosedAi, thread_id, role, content: string,
  file_ids: seq[string] = @[],
  metadata: Table[string, string] = initTable[string, string](),
): Future[CAMessage] {.async.} =
  var client = self.newAssistantClient

  let uri = HOST / "threads" / thread_id / "messages"

  var params = %*{ "role": role, "content": content }
  if file_ids.len > 0:
    params["file_ids"] = %*file_ids
  if metadata.len > 0:
    params["metadata"] = %*metadata

  let res = await client.request(uri, params, HttpPost)
  return res.initMessage

proc listMessages*(self: ClosedAi, thread_id: string,
  opts = initListOptions()
): Future[CAList[CAMessage]] {.async.} =
  var client = self.newAssistantClient
  let uri = HOST / "threads" / thread_id / "messages"
  let params = opts.toJson
  let resp = await client.request(uri, params)
  return initList[CAMessage](resp, initMessage)

# Run

proc createRun*(self: ClosedAi, thread_id, assistant_id: string,
  # TODO
): Future[CARun] {.async.} =
  var client = self.newAssistantClient
  let uri = HOST / "threads" / thread_id / "runs"
  let params = %*{ "assistant_id": assistant_id }
  # TODO
  let resp = await client.request(uri, params, HttpPost)
  return initRun(resp)

proc listRuns*(self: ClosedAi, thread_id: string,
  opts = initListOptions()
): Future[CAList[CARun]] {.async.} =
  var client = self.newAssistantClient
  let uri = HOST / "threads" / thread_id / "runs"
  let params = opts.toJson
  let resp = await client.request(uri, params)
  return initList[CARun](resp, initRun)

proc retrieveRun*(self: ClosedAi, thread_id, run_id: string): Future[CARun] {.async.} =
  var client = self.newAssistantClient
  let uri = HOST / "threads" / thread_id / "runs" / run_id
  let resp = await client.request(uri)
  return initRun(resp)

proc listRunSteps*(self: ClosedAi, thread_id, run_id: string,
  opts = initListOptions()
): Future[CAList[CARunStep]] {.async.} =
  var client = self.newAssistantClient
  let uri = HOST / "threads" / thread_id / "runs" / run_id / "steps"
  let params = opts.toJson
  let resp = await client.request(uri, params)
  return initList[CARunStep](resp, initRunStep)
