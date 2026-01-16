echo "Do you want to set up a new SSH key for the system? (y/n)"
read response
if [ "$response" = "y" ]
then
  new-ssh-key
else
  echo "No SSH key will be set up. You can always set one up later by running \"new-ssh-key\"."
fi
