defmodule AiBrandAgent.Agents.ContentAgent do
  @moduledoc """
  Orchestrates content generation via the Gemini LLM.

  Receives a topic, builds a prompt, calls the LLM, and persists the
  generated post as a draft. Stateless beyond minimal tracking —
  the database is the source of truth.

  Pass optional `opts` for multi-variant runs (`:variant`, `:generation_run_id`, etc.).
  """

  use GenServer

  require Logger

  alias AiBrandAgent.Accounts
  alias AiBrandAgent.AI.LLMClient
  alias AiBrandAgent.AI.PromptBuilder
  alias AiBrandAgent.Services.ContentService

  @pubsub AiBrandAgent.PubSub

  # ── Client API ──────────────────────────────────────────────────────

  def start_link(opts \\ []) do
    GenServer.start_link(__MODULE__, opts, name: __MODULE__)
  end

  @doc """
  Generate a social media post for the given topic/user/platform.

  Optional `opts`:
  - `:variant` — `:story | :insight | :punchy`
  - `:generation_run_id`, `:variant_index`, `:style_tag`
  - `:brand_context` — override (otherwise loaded from Accounts)
  - `:performance_hints` — extra string for the prompt

  Returns `{:ok, post}` or `{:error, reason}`.
  """
  def generate(topic, user_id, platform, opts \\ []) do
    GenServer.call(__MODULE__, {:generate, topic, user_id, platform, opts}, :timer.seconds(240))
  end

  # ── Server callbacks ────────────────────────────────────────────────

  @impl true
  def init(_opts) do
    {:ok, %{}}
  end

  @impl true
  def handle_call({:generate, topic, user_id, platform, opts}, _from, state) do
    result = do_generate(topic, user_id, platform, opts)
    {:reply, result, state}
  end

  # ── Private ─────────────────────────────────────────────────────────

  defp do_generate(topic, user_id, platform, opts) do
    brand_context =
      Keyword.get(opts, :brand_context) || Accounts.brand_promotion_context_for_llm(user_id)

    variant = Keyword.get(opts, :variant)
    hints = Keyword.get(opts, :performance_hints) || ""

    prompt =
      PromptBuilder.build(:post_from_topic, %{
        topic: topic,
        platform: platform,
        brand_context: brand_context,
        variant: variant,
        performance_hints: hints
      })

    base_attrs = %{
      user_id: user_id,
      topic_id: topic.id,
      platform: to_string(platform),
      content: nil,
      status: "draft"
    }

    attrs =
      base_attrs
      |> put_if_present(:generation_run_id, Keyword.get(opts, :generation_run_id))
      |> put_if_present(:variant_index, Keyword.get(opts, :variant_index))
      |> put_if_present(:style_tag, Keyword.get(opts, :style_tag))

    with {:ok, content} <- LLMClient.complete(prompt),
         attrs = Map.put(attrs, :content, content),
         {:ok, post} <- ContentService.create_post(attrs) do
      broadcast_new_post(post)
      {:ok, post}
    else
      {:error, reason} = err ->
        Logger.error("Content generation failed: #{inspect(reason)}")
        err
    end
  end

  defp put_if_present(map, _k, nil), do: map
  defp put_if_present(map, k, v), do: Map.put(map, k, v)

  defp broadcast_new_post(post) do
    Phoenix.PubSub.broadcast(
      @pubsub,
      "posts:user:#{post.user_id}",
      {:new_post, post}
    )
  end
end
