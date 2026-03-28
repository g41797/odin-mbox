# The C++ Decision

Many years ago, I worked as a network programmer in a big corporation.\  
The main (and only) programming language was C.  

It was the time when C++ was rising.  

We had to develop a project for inter-computer data transfer.\  
I prepared a design and, as usual, provided tables with calculated memory requirements for different numbers of clients, types of data, and so on — business as usual (at least for network programmers).  

A C++ programmer also brought his design.  

After both our presentations, the big bosses asked one question:  
“What is required from the computer to provide this functionality without harming image processing?”  

I was proud — I had the answer immediately. I had the table.  

The C++ programmer looked a bit confused. He said:\  
“I don’t know the answer, because I get everything from the operating system.”  

We were asked to wait outside the meeting room for five minutes.  

The decision came:\  
**Use C++, because it has no resource problems — everything is provided by the operating system.**
