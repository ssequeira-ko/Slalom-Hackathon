import { LightningElement, wire } from 'lwc';
import getDashboard from '@salesforce/apex/FitnessPortalController.getDashboard';
export default class FitnessDashboard extends LightningElement {
  data; errorMessage; justWon=false; priorAwards='';
  @wire(getDashboard) wired({data,error}) {
    if(data) { this.data={...data, team:data.team.map(x=>({...x,salesFormatted:this.currency(x.sales)}))}; this.errorMessage=undefined;
      const awards=(data.newAwards||[]).join('|'); const today=new Date().toISOString().slice(0,10); if((this.priorAwards && awards!==this.priorAwards) || (data.latestAwardDate===today && !this.priorAwards)) this.justWon=true; this.priorAwards=awards;
    } else if(error) { this.errorMessage=error.body?.message || 'We could not load your sales dashboard.'; }
  }
  currency(value){return new Intl.NumberFormat('en-US',{style:'currency',currency:'USD',maximumFractionDigits:0}).format(value||0)}
  get salesFormatted(){return this.currency(this.data?.personalSales)} get goalFormatted(){return this.currency(this.data?.goalAmount)}
  get goalCaption(){return this.data?.goalAmount>0?`${this.currency(this.data.personalSales)} earned toward your goal`:'Ask your team lead to set a sales goal.'}
  get nextAwardLabel(){return this.data?.nextAwardName||'All milestones reached'}
  get nextAwardCaption(){return this.data?.nextAwardAt?`${Math.max(0,this.data.nextAwardAt-this.data.points)} points to unlock`:'You have earned every active award.'}
  get progressStyle(){return `width:${Math.min(100,this.data?.goalPercent||0)}%`}
  get pointsProgressStyle(){const p=this.data?.nextAwardAt?Math.min(100,(this.data.points/this.data.nextAwardAt)*100):100;return `width:${p}%`}
  get hasTeam(){return (this.data?.team?.length||0)>0} get teamCount(){return this.data?.team?.length||0}
  get hasAwards(){return (this.data?.newAwards?.length||0)>0}
  dismissWin(){this.justWon=false}
}