public with sharing class FitnessPortalController {
    public class DashboardData {
        @AuraEnabled public String memberName {get;set;}
        @AuraEnabled public Decimal personalSales {get;set;}
        @AuraEnabled public Decimal goalAmount {get;set;}
        @AuraEnabled public Integer goalPercent {get;set;}
        @AuraEnabled public Decimal points {get;set;}
        @AuraEnabled public Decimal nextAwardAt {get;set;}
        @AuraEnabled public String nextAwardName {get;set;}
        @AuraEnabled public List<TeamRow> team {get;set;}
        @AuraEnabled public List<String> newAwards {get;set;}
        @AuraEnabled public String latestAwardDate {get;set;}
    }
    public class TeamRow { @AuraEnabled public String name {get;set;} @AuraEnabled public Decimal sales {get;set;} @AuraEnabled public Decimal points {get;set;} }

    @AuraEnabled(cacheable=true)
    public static DashboardData getDashboard() {
        Id contactId = [SELECT ContactId FROM User WHERE Id=:UserInfo.getUserId()].ContactId;
        if (contactId == null) throw new AuraHandledException('Your portal user is not linked to a Contact. Ask an administrator to connect your Sales Team Member profile.');
        List<Sales_Team_Member__c> found = [SELECT Id, Name, Total_Points__c, Contact__r.Name FROM Sales_Team_Member__c WHERE Contact__c=:contactId AND Status__c='Active' LIMIT 1];
        if (found.isEmpty()) throw new AuraHandledException('No active Sales Team Member profile is linked to your login.');
        Sales_Team_Member__c me=found[0]; DashboardData d=new DashboardData(); d.memberName=me.Contact__r.Name; d.points=me.Total_Points__c==null?0:me.Total_Points__c; d.team=new List<TeamRow>(); d.newAwards=new List<String>();
        Date today=Date.today(); Date monthStart=Date.newInstance(today.year(),today.month(),1);
        List<Sales_Goal__c> goals=[SELECT Sales_Target__c FROM Sales_Goal__c WHERE Sales_Team_Member__c=:me.Id AND Start_Date__c<=:today AND End_Date__c>=:today ORDER BY End_Date__c LIMIT 1];
        d.goalAmount=goals.isEmpty() || goals[0].Sales_Target__c==null ? 0 : goals[0].Sales_Target__c;
        AggregateResult[] own=[SELECT SUM(Amount__c) total FROM Sales_Transaction__c WHERE Sales_Team_Member__c=:me.Id AND Status__c='Qualified' AND Sale_Date__c>=:monthStart AND Sale_Date__c<=:today];
        d.personalSales=(Decimal)own[0].get('total'); if(d.personalSales==null)d.personalSales=0;
        d.goalPercent=d.goalAmount<=0?0:Math.min(100,(Integer)((d.personalSales/d.goalAmount*100).setScale(0,RoundingMode.DOWN)));
        // Walk the recruiting tree in bounded breadth-first passes; only descendants are returned.
        Set<Id> seen=new Set<Id>{me.Id}; Set<Id> frontier=new Set<Id>{me.Id};
        for(Integer depth=0;depth<10 && !frontier.isEmpty();depth++) { List<Sales_Team_Member__c> children=[SELECT Id FROM Sales_Team_Member__c WHERE Sponsor__c IN :frontier AND Status__c='Active' LIMIT 500]; frontier=new Set<Id>(); for(Sales_Team_Member__c c:children) if(!seen.contains(c.Id)){seen.add(c.Id);frontier.add(c.Id);} }
        seen.remove(me.Id);
        if(!seen.isEmpty()) {
            Map<Id,Sales_Team_Member__c> childMap=new Map<Id,Sales_Team_Member__c>([SELECT Id, Contact__r.Name, Total_Points__c FROM Sales_Team_Member__c WHERE Id IN :seen]);
            Map<Id,Decimal> sums=new Map<Id,Decimal>();
            for(AggregateResult ar:[SELECT Sales_Team_Member__c mid, SUM(Amount__c) total FROM Sales_Transaction__c WHERE Sales_Team_Member__c IN :seen AND Status__c='Qualified' AND Sale_Date__c>=:monthStart AND Sale_Date__c<=:today GROUP BY Sales_Team_Member__c]) sums.put((Id)ar.get('mid'),(Decimal)ar.get('total'));
            for(Sales_Team_Member__c child:childMap.values()){TeamRow row=new TeamRow();row.name=child.Contact__r.Name;row.sales=sums.containsKey(child.Id)?sums.get(child.Id):0;row.points=child.Total_Points__c==null?0:child.Total_Points__c;d.team.add(row);}
        }
        List<Award_Definition__c> next=[SELECT Name, Points_Threshold__c FROM Award_Definition__c WHERE Active__c=true AND Points_Threshold__c>:d.points ORDER BY Points_Threshold__c LIMIT 1];
        if(!next.isEmpty()){d.nextAwardAt=next[0].Points_Threshold__c;d.nextAwardName=next[0].Name;}
        for(Member_Award__c a:[SELECT Award_Definition__r.Name, Awarded_On__c FROM Member_Award__c WHERE Sales_Team_Member__c=:me.Id ORDER BY CreatedDate DESC LIMIT 5]) { d.newAwards.add(a.Award_Definition__r.Name); if (d.latestAwardDate == null) d.latestAwardDate=String.valueOf(a.Awarded_On__c); }
        return d;
    }
}
