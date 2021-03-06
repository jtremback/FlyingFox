defmodule Listener do
  use GenServer
	@name __MODULE__
  def init(:ok) do {:ok, []} end
  def start_link() do GenServer.start_link(__MODULE__, :ok, [name: @name]) end
  def export(l) do GenServer.call(@name, {hd(l), self(), tl(l)}) end
  def handle_call({type, s, args}, _from, _) do
    Task.start(fn() -> GenServer.reply(_from, main(type, args)) end)
    {:noreply, []}
  end
	def sig(o, f) do if CryptoSign.verify_tx(hd(o)) do f.(hd(o).data) else	"bad sig"	end end
	def main(type, args) do
    case type do
			"kv" -> args |> hd |> KV.get
      "add_blocks" ->
				Task.start_link(fn() -> BlockAbsorber.absorb(hd(args)) end)
				0
      "pushtx" -> Mempool.add_tx(hd(args))
      "txs" -> Mempool.txs
      "height" -> KV.get("height")
      "block" -> Blockchain.get_block(hd(args))
      "blocks" ->
				a = hd(args)
				if is_binary(a) do a = String.to_integer(a) end
				b = hd(tl(args))
				if is_binary(a) do b = String.to_integer(b) end
				blocks(a, b)
      "add_peer" -> Peers.add_peer(hd(args))
      "all_peers" -> Enum.map(Peers.get_all, fn({x, y}) -> y end)
      "status" ->
        h = KV.get("height")
        block = Blockchain.get_block(h)
        if block.data==nil do block = %{data: 1} end
        %Status{height: h, hash: Blockchain.blockhash(block), pubkey: Keys.pubkey}
			"cost" -> MailBox.cost
			"register" ->
        x = hd(args)
			  MailBox.register(x.payment, x.pub)
			"delete_account" -> args |> sig(fn(x) -> MailBox.delete_account(x.pub) end)
			"send_message" ->
        x = hd(args)
				IO.puts("listener send message #{inspect x}")
				m = %{msg: x.msg[:msg], key: x.msg[:key]}
				out = MailBox.send(x.payment, x.to, m)
				IO.puts("listener send message out #{inspect out}")
				out 
			"pop" -> args |> sig(&(MailBox.pop(&1.pub)))
			"inbox_size" -> args |> sig(&(MailBox.size(&1.pub)))
			"accept" -> ChannelManager.accept(hd(args), max(Constants.min_channel_spend, hd(tl(args))))
			"mail_nodes" -> MailNodes.all
      x -> IO.puts("listener is not a command #{inspect x}")
    end
  end
  def blocks(start, finish, out \\ []) do
    finish |> min(KV.get("height")) |> blocks_helper(start, out)
  end
  def blocks_helper(finish, start, out) do
    block = Blockchain.get_block(start)
    cond do
			byte_size(PackWrap.pack(out)) > Constants.message_size -> tl(out)
      start < 0 -> blocks_helper(finish, 1, out)
      start > finish -> out
      block == nil -> blocks_helper(finish, start+1, out)
      true -> blocks_helper(finish, start+1, [block|out])
    end
  end
end
