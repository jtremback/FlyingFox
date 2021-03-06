defmodule ChannelBlock do
	#It should be modified so that "amount" means how much we want to change the channel by, no the final amount.

	defstruct nonce: 0, pub: "", pub2: nil, secret_hash: nil, bets: [], time: 0, delay: 10, fast: false, amount: 0
  #maybe we should stop any channel tx of different types from coexisting in the same block.
	#must specify which hashes are new, and which have existed before. <- NOT a part of the channel state.
	#if one tx is creating a new decision, then don't let any other tx in that same block bet on the same decision.
	def check(tx, txs \\ [], backcheck \\ true) do
    da = tx.data
		channel = KV.get(ToChannel.key(da.pub, da.pub2))
		repeats = txs |> Enum.filter(&(&1.data.__struct__ == tx.data.__struct__ and (&1.data.pub == tx.data.pub and &1.data.pub2 == tx.data.pub2)))
		d = 1
		if channel.pub != da.pub do d = -1 end
    cond do
			channel == nil ->
				IO.puts("channel doesn't exist yet, so you can't spend on it.")
				false
			da.bets != [] ->
				IO.puts("bets not yet programmed")
				false
			channel.nonce != 0 and backcheck ->
				IO.puts("a channel block was already published for this channel. ")
				false
			repeats != [] ->
				IO.puts("no repeats")
				false
      not CryptoSign.check_sig2(tx) ->
				IO.puts("bad sig2")
				false
			channel.amount - (da.amount * d) < 0 ->
				IO.puts("no counterfeiting: need #{inspect d * da.amount} have #{inspect channel.amount}")
				false
			channel.amount2 + (da.amount * d) < 0 ->
				IO.puts("conservation of money: need #{inspect da.amount * d} have #{inspect channel.amount2}")
				false
      da.secret_hash != nil and da.secret_hash != DetHash.doit(tx.meta.secret) ->
				IO.puts("secret does not match")
				false
      true -> true
    end
		#fee can be paid by either or both.
	end
	def update(tx, d) do
    da = tx.data
		channel = ToChannel.key(da.pub, da.pub2)
		current = KV.get(channel)
		if da.fast do
			TxUpdate.sym_increment(da.pub, :amount, current.amount+da.amount, d)
			TxUpdate.sym_increment(da.pub2, :amount, current.amount2-da.amount, d)
			#should delete the state.
		else
			TxUpdate.sym_replace(channel, :time, 0, KV.get("height"), d)
			TxUpdate.sym_replace(channel, :nonce, 0, da.nonce, d)
			TxUpdate.sym_increment(channel, :amount, da.amount, d)
			TxUpdate.sym_increment(channel, :amount2, -da.amount, d)
		end
	end
end
