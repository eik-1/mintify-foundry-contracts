const ticker = args[0];
const apiRequest = Functions.makeHttpRequest({
  url: `https://chainlink-wine.vercel.app/api/alpha/${ticker}`,
  headers: {
    accept: "application/json",
  },
});

const [response] = await Promise.all([apiRequest]);

const stockPrice = response.data.price;
console.log(`Stock Price: $${stockPrice}`);

return Functions.encodeUint256(Math.round(stockPrice * 1e18));
