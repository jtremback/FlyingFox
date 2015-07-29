#channel manager needs to keep track of the highest-nonced transaction from the peer, and it also needs to keep track of the highest-nonced transaction we sent to the peer.
#eventually we need to store multiple hash_locked transactions from the peer.
defmodule ChannelManager do
	defstruct recieved: %CryptoSign{data: %ChannelBlock{}}, sent: %CryptoSign{data: %ChannelBlock{}}#, hash_locked: []
  use GenServer
  @name __MODULE__
	def db_lock(f) do
		{status, db} = Exleveldb.open(System.cwd <> "/channeldb")#different in windows?
		case status do
			:ok ->
				#we have a lock on the db, so no one else can use it till we are done.
				out = f.(db)
				Exleveldb.close(db)#unlock
				out
			:db_open ->#someone else has a lock on the db.
				:timer.sleep(50)
				db_lock(f)
			true -> IO.puts("db broke")
		end
	end
	def put(key, val) do Task.start_link(fn() -> db_lock(fn(db) -> Exleveldb.put(db, key, PackWrap.pack(val), []) end) end) end
  def init(_) do
		{:ok, db_lock(fn(db) ->
					Exleveldb.fold(
						db,
						fn({key, value}, acc) -> HashDict.put(acc, key, PackWrap.unpack(value)) end,
						%HashDict{}) end)}
	end
  def start_link() do   GenServer.start_link(__MODULE__, 0, name: @name) end
	def get(pub) do       GenServer.call(@name, {:get, pub}) end
  def get_all do        GenServer.call(@name, :get_all) end
  def handle_call(:get_all, _from, mem) do {:reply, mem, mem} end
  def handle_call({:get, pub}, _from, mem) do
		out = mem[pub]
		if out == nil do
			out = %ChannelManager{sent: %CryptoSign{data: %ChannelBlock{pub: Keys.pubkey, pub2: pub}}}
		end
		{:reply, out, mem} end
  def handle_cast({:send, pub, channel},  mem) do
		out = mem[pub]
		if out == nil do out = %ChannelManager{} end
		out = %{out | sent: channel}
		put(pub, out)
		{:noreply, HashDict.put(mem, pub, out)}
	end
	def handle_cast({:recieve, pub, channel},  mem) do
		out = mem[pub]
		if out == nil do out = %ChannelManager{} end
		out = %{out | recieved: channel}
		put(pub, out)
		{:noreply, HashDict.put(mem, pub, out)}
	end
	def other(tx) do
		tx = [tx.data.pub, tx.data.pub2] |> Enum.filter(&(&1 != Keys.pubkey))
		cond do
			tx == [] -> Keys.pubkey
			true -> hd(tx)
		end
	end
	def accept(tx, min_amount \\ -Constants.initial_coins, mem \\ []) do
		cond do
			tx == nil ->
				IO.puts("no payment")
				false
			accept_check(tx, min_amount, mem) ->
				other = other(tx)
				GenServer.cast(@name, {:recieve, other, tx})
				d = 1
				if tx.data.pub2 == Keys.pubkey do d = d * -1 end
				tx.data.amount * d
			true ->
				IO.puts("bad payment #{inspect tx}")
				false
		end
	end
	def accept_check(tx, min_amount \\ -Constants.initial_coins, mem \\ []) do
		other = other(tx)
		d = -1
		d2 = -1
		if Keys.pubkey == tx.data.pub do d = d * -1 end
		if mem != [] do x = mem[other] else x = get(other) end
		x = x |> top_block
		if Keys.pubkey == x.data.pub do d2 = d2 * -1 end
		if is_binary(min_amount) do min_amount = String.to_integer(min_amount) end
		cond do
			#checking if nil is a joke. you need to see if it is a valid signature or not.
			not Keys.pubkey in [tx.data.pub, tx.data.pub2] ->
				IO.puts("channel isn't for me")
				false
			tx.data.pub == Keys.pubkey and not (CryptoSign.check_sig2(tx)) ->
				IO.puts("2 should be signed by partner")
				false
			tx.data.pub2 == Keys.pubkey and not (CryptoSign.verify_tx(tx))->
				IO.puts("1 should be signed by partner")
				false
			not (((d2 * x.data.amount) - (d * tx.data.amount)) >= min_amount) ->
				IO.puts("x #{inspect x}")
				IO.puts("tx #{inspect tx}")
				IO.puts("didn't spend enough #{inspect (d2 * x.data.amount) - (d * tx.data.amount)}")
				IO.puts("min amount #{inspect min_amount}")
				false
			not (:Elixir.CryptoSign == tx.__struct__) ->
				IO.puts("unsigned")
				false
			not (:Elixir.ChannelBlock == tx.data.__struct__) ->
				IO.puts("isn't a channel block")
				false
			not ChannelBlock.check(Keys.sign(tx)) ->
				IO.puts("isn't a valid channel block")
				false
			not (tx.data.nonce > x.data.nonce) ->
				IO.puts("nonce is too low")
				false#eventually we should keep the biggest spendable block, and all bigger ones.
			true -> true
		end
	end
	def top_block(c) do
		[c.sent, c.recieved]
		|> Enum.sort(&(&1.data.nonce > &2.data.nonce))
		|> hd
	end
	def spend(pub, amount, default \\ Constants.default_channel_balance) do
		if amount > Constants.min_channel_spend do
			spend_helper(pub, amount, default)
		end
	end
	def spend_helper(pub, amount, default) do
		cb = get(pub) |> top_block
		cb = cb.data
		IO.puts("channel manager spend #{inspect cb}")
		pub1 = cb.pub
		if is_binary(amount) do amount = String.to_integer(amount) end
		on_chain = KV.get(ToChannel.key(pub, Keys.pubkey))
		cb = %{cb | pub: Keys.pubkey, pub2: pub}
		d = 1
		if pub1 != cb.pub do d = -1 end
		if Keys.pubkey != cb.pub do amount = -amount end
		cb = %{cb | amount: (d * cb.amount) + amount, nonce: cb.nonce + 1} |> Keys.sign
		if on_chain.amount <= amount or on_chain.amount2 <= -amount do
			IO.puts("not enough money in the channel to spend that much")
			IO.puts("on chain #{inspect on_chain}")
			IO.puts("amount #{inspect amount}")
		else
			GenServer.cast(@name, {:send, pub, cb})
		end
		cb
	end
end

