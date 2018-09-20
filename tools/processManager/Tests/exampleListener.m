% A processManager object issues a notification when its process finishes.
% Listening for this notification is as simple as attaching a listener and
% defining a callback for the event.
%
% http://www.mathworks.com/help/matlab/matlab_oop/learning-to-use-events-and-listeners.html

cmd = 'ping www.google.com';


% Create an object and attach the listener
p = processManager('command',cmd,...
                   'id','ping',...
                   'printStdout',false,...
                   'keepStdout',true);               
addlistener(p.state,'exit',@exitHandler);


function exitHandler(src,data)
   fprintf('\n');
   fprintf('Process "%s" exited with exitValue = %g\n',src.id,src.exitValue);
   fprintf('Event name %s\n',data.EventName);   
   fprintf('\n');
   if ~isempty(src.stdout)
       fprintf('StdOut of the process:\n\n');
       processManager.printStream(src.stdout,'',80);
   end   
end
