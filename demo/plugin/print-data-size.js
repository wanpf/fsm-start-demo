pipy({
})

  .pipeline()

  // send
  .handleData(
    dat => (
      console.log('==============[TcpTraffic] send data size:', dat?.size)
    )
  )

  .chain()

  // receive
  .handleData(
    dat => (
      console.log('==============[TcpTraffic] receive data size:', dat?.size)
    )
  )