public class ContactAndLeadSearch {
    public static List<List<sObject>> searchContactsAndLeads(String Name){
      
        List<List<sObject>> searchList = [FIND :Name IN ALL FIELDS
                    RETURNING Lead(FirstName,LastName),Contact(FirstName,LastName)];
        return searchList;
    }
}