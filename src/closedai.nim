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

proc newClosedAi*(apiKey: string,
                  organization = "",
                  user = "",
                  proxy: Proxy = nil,
                  ): ClosedAi =
  result.new
  result.apiKey = apiKey
  result.organization = organization
  result.user = user
  result.proxy = proxy

proc newClient( self: ClosedAi,
                ): AsyncHttpClient =
  result = newAsyncHttpClient(proxy = self.proxy)
  result.headers = newHttpHeaders({
    "Content-Type": "application/json",
    "Authorization": &"Bearer {self.apiKey}",
  })
  if self.organization.len > 0:
    result.headers["OpenAI-Organization"] = self.organization

proc request( client: AsyncHttpClient,
              url: Uri,
              params: JsonNode = %*{},
              httpMethod = HttpGet,
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

proc initListOptions*(limit = 20,
                      order = "desc",
                      after = "",
                      before = ""
                      ): CAListOptions {.inline.} =
  CAListOptions(
    limit: limit,
    order: order,
    after: after,
    before: before,
  )

proc toParams(self: CAListOptions,
              ): JsonNode =
  result = %*{ "limit": self.limit, "order": self.order }
  if self.after.len > 0:
    result["after"] = %*self.after
  if self.before.len > 0:
    result["before"] = %*self.before

# Assistants

proc newAssistantClient(self: ClosedAi
                        ): AsyncHttpClient =
  result = self.newClient
  result.headers["OpenAI-Beta"] = "assistants=v1"

proc createAssistant*(self: ClosedAi,
                      e: CAAssistant,
                      ): Future[CAAssistant] {.async.} =
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
    params["tools"] = %*(e.tools)
  if e.file_ids.len > 0:
    params["file_ids"] = %*(e.file_ids)
  if e.metadata.len > 0:
    params["metadata"] = %*(e.metadata)

  let res = await client.request(uri, params, HttpPost)
  return res.initAssistant

proc listAssistants*( self: ClosedAi,
                      opts = initListOptions(),
                      ): Future[CAList[CAAssistant]] {.async.} =
  var client = self.newAssistantClient
  let uri = HOST / "assistants"
  let params = opts.toParams
  let resp = await client.request(uri, params)
  return initList[CAAssistant](resp, initAssistant)

proc retrieveAssistant*(self: ClosedAi,
                        assistantId: string,
                        ): Future[CAAssistant] {.async.} =
  var client = self.newAssistantClient
  let uri = HOST / "assistants" / assistantId
  let res = await client.request(uri)
  return res.initAssistant

proc modifyAssistant*(self: ClosedAi,
                      e: CAAssistant,
                      ): Future[CAAssistant] {.async.} =
  var client = self.newAssistantClient
  let uri = HOST / "assistants" / e.id
  var params = %*{
    "model": e.model,
    "name": e.name,
    "description": e.description,
    "instructions": e.instructions,
    "tools": e.tools,
    "file_ids": e.file_ids,
    "metadata": e.metadata,
  }
  let res = await client.request(uri, params, HttpPost)
  return res.initAssistant

proc deleteAssistant*(self: ClosedAi,
                      assistantId: string,
                      ): Future[CADelete] {.async.} =
  var client = self.newAssistantClient
  let uri = HOST / "assistants" / assistantId
  let res = await client.request(uri, httpMethod = HttpDelete)
  return res.initDelete

# Thread

type
  CAMessageParam* = object
    role*: string
    content*: string
    file_ids*: seq[string]
    metadata*: Table[string, string]


proc createThread*( self: ClosedAi,
                    messages: seq[CAMessageParam] = @[],
                    metadata: Table[string, string] = initTable[string, string](),
                    ): Future[CAThread] {.async.} =
  var client = self.newAssistantClient
  let uri = HOST / "threads"
  var params = %*{
    "messages": messages,
    "metadata": metadata,
  }
  let res = await client.request(uri, params, HttpPost)
  return res.initThread

proc retrieveThread*( self: ClosedAi,
                      thread_id: string,
                      ): Future[CAThread] {.async.} =
  var client = self.newAssistantClient
  let uri = HOST / "threads" / thread_id
  let res = await client.request(uri)
  return res.initThread

proc modifyThread*( self: ClosedAi,
                    e: CAThread,
                    ): Future[CAThread] {.async.} =
  var client = self.newAssistantClient
  let uri = HOST / "threads" / e.id
  let params = %*{ "metadata": e.metadata }
  let res = await client.request(uri, params, HttpPost)
  return res.initThread

proc deleteThread*( self: ClosedAi,
                    thread_id: string,
                    ): Future[CADelete] {.async.} =
  var client = self.newAssistantClient
  let uri = HOST / "threads" / thread_id
  let res = await client.request(uri, httpMethod = HttpDelete)
  return res.initDelete

# Message

proc createMessage*(self: ClosedAi,
                    thread_id: string,
                    msg: CAMessageParam,
                    ): Future[CAMessage] {.async.} =
  var client = self.newAssistantClient
  let uri = HOST / "threads" / thread_id / "messages"
  var params = %*msg
  let res = await client.request(uri, params, HttpPost)
  return res.initMessage

proc listMessages*( self: ClosedAi,
                    thread_id: string,
                    opts = initListOptions()
                    ): Future[CAList[CAMessage]] {.async.} =
  var client = self.newAssistantClient
  let uri = HOST / "threads" / thread_id / "messages"
  let params = opts.toParams
  let resp = await client.request(uri, params)
  return initList[CAMessage](resp, initMessage)

# Run

proc createRun*(self: ClosedAi,
                thread_id, assistant_id: string,
                model = "",
                instructions = "",
                additional_instructions = "",
                tools: seq[CATool] = @[],
                metadata: Table[string, string] = initTable[string, string](),
                ): Future[CARun] {.async.} =
  var client = self.newAssistantClient
  let uri = HOST / "threads" / thread_id / "runs"

  let params = %*{ "assistant_id": assistant_id }
  if model.len > 0:
    params["model"] = %*(model)
  if instructions.len > 0:
    params["instructions"] = %*(instructions)
  if additional_instructions.len > 0:
    params["additional_instructions"] = %*(additional_instructions)
  if tools.len > 0:
    params["tools"] = %*(tools)
  if metadata.len > 0:
    params["metadata"] = %*(metadata)

  let resp = await client.request(uri, params, HttpPost)
  return initRun(resp)

proc listRuns*( self: ClosedAi,
                thread_id: string,
                opts = initListOptions(),
                ): Future[CAList[CARun]] {.async.} =
  var client = self.newAssistantClient
  let uri = HOST / "threads" / thread_id / "runs"
  let params = opts.toParams
  let resp = await client.request(uri, params)
  return initList[CARun](resp, initRun)

proc retrieveRun*(self: ClosedAi,
                  thread_id, run_id: string,
                  ): Future[CARun] {.async.} =
  var client = self.newAssistantClient
  let uri = HOST / "threads" / thread_id / "runs" / run_id
  let resp = await client.request(uri)
  return initRun(resp)

proc listRunSteps*( self: ClosedAi,
                    thread_id, run_id: string,
                    opts = initListOptions(),
                    ): Future[CAList[CARunStep]] {.async.} =
  var client = self.newAssistantClient
  let uri = HOST / "threads" / thread_id / "runs" / run_id / "steps"
  let params = opts.toParams
  let resp = await client.request(uri, params)
  return initList[CARunStep](resp, initRunStep)

# Models

proc listModels*( self: ClosedAi
                  ): Future[CAList[CAModel]] {.async.} =
  var client = self.newClient
  let url = HOST / "models"
  let res = await client.request(url)
  return initList[CAModel](res, initModel)
